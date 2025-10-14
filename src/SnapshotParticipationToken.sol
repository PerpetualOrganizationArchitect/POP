// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*──────────────────── OpenZeppelin v5.3 Upgradeables ─────────────*/
import "@openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ContextUpgradeable.sol";
import "@openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

/*────────────── External Hats interface ─────────────*/
import {IHats} from "lib/hats-protocol/src/Interfaces/IHats.sol";
import {HatManager} from "./libs/HatManager.sol";

/**
 * @title SnapshotParticipationToken
 * @notice ParticipationToken with built-in snapshot functionality for distribution safety
 * @dev Extends ParticipationToken with ERC20Snapshot-like capabilities
 */
contract SnapshotParticipationToken is Initializable, ERC20Upgradeable, ReentrancyGuardUpgradeable {
    /*──────────── Errors ───────────*/
    error NotTaskOrEdu();
    error NotApprover();
    error NotMember();
    error NotRequester();
    error RequestUnknown();
    error AlreadyApproved();
    error AlreadySet();
    error InvalidAddress();
    error ZeroAmount();
    error TransfersDisabled();
    error Unauthorized();
    error InvalidSnapshot();

    /*──────────── Types ───────────*/
    struct Request {
        address requester;
        uint96 amount;
        bool approved;
        string ipfsHash;
    }

    struct Snapshot {
        uint256 blockNumber;
        uint256 totalSupply;
        mapping(address => uint256) balances;
        mapping(address => bool) hasBalance;
    }

    /*──────────── Hat Type Enum ───────────*/
    enum HatType {
        MEMBER,
        APPROVER
    }

    /*──────────── ERC-7201 Storage ───────────*/
    /// @custom:storage-location erc7201:poa.snapshotparticipationtoken.storage
    struct Layout {
        address taskManager;
        address educationHub;
        IHats hats;
        address executor;
        uint256 requestCounter;
        mapping(uint256 => Request) requests;
        uint256[] memberHatIds;
        uint256[] approverHatIds;
        // Snapshot storage
        uint256 currentSnapshotId;
        mapping(uint256 => Snapshot) snapshots;
        mapping(address => uint256[]) accountSnapshotIds;
    }

    // keccak256("poa.snapshotparticipationtoken.storage") → unique, collision-free slot
    bytes32 private constant _STORAGE_SLOT = 0xd49c4cc718f2f9e8d168c340989dd4f66bf6674fc7217665b075b167908f4ee2;

    function _layout() private pure returns (Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    /*──────────── Events ──────────*/
    event TaskManagerSet(address indexed taskManager);
    event EducationHubSet(address indexed educationHub);
    event Requested(uint256 indexed id, address indexed requester, uint96 amount, string ipfsHash);
    event RequestApproved(uint256 indexed id, address indexed approver);
    event RequestCancelled(uint256 indexed id, address indexed caller);
    event MemberHatSet(uint256 hat, bool allowed);
    event ApproverHatSet(uint256 hat, bool allowed);
    event SnapshotCreated(uint256 indexed snapshotId, uint256 blockNumber);

    /*─────────── Initialiser ──────*/
    function initialize(
        address executor_,
        string calldata name_,
        string calldata symbol_,
        address hatsAddr,
        uint256[] calldata initialMemberHats,
        uint256[] calldata initialApproverHats
    ) external initializer {
        if (hatsAddr == address(0) || executor_ == address(0)) revert InvalidAddress();

        __ERC20_init(name_, symbol_);
        __ReentrancyGuard_init();

        Layout storage l = _layout();
        l.hats = IHats(hatsAddr);
        l.executor = executor_;

        // Set initial member hats
        for (uint256 i; i < initialMemberHats.length;) {
            HatManager.setHatInArray(l.memberHatIds, initialMemberHats[i], true);
            emit MemberHatSet(initialMemberHats[i], true);
            unchecked {
                ++i;
            }
        }

        // Set initial approver hats
        for (uint256 i; i < initialApproverHats.length;) {
            HatManager.setHatInArray(l.approverHatIds, initialApproverHats[i], true);
            emit ApproverHatSet(initialApproverHats[i], true);
            unchecked {
                ++i;
            }
        }
    }

    /*────────── Snapshot Functions ─────────*/
    
    /**
     * @notice Creates a new snapshot
     * @return snapshotId The ID of the created snapshot
     * @dev Only callable by executor or during proposal creation
     */
    function snapshot() public returns (uint256 snapshotId) {
        _checkExecutor();
        return _snapshot();
    }
    
    /**
     * @notice Creates a new snapshot with specified holders
     * @param holders Array of addresses to snapshot
     * @return snapshotId The ID of the created snapshot
     */
    function snapshotWithHolders(address[] calldata holders) public returns (uint256 snapshotId) {
        _checkExecutor();
        Layout storage l = _layout();
        
        snapshotId = ++l.currentSnapshotId;
        Snapshot storage snap = l.snapshots[snapshotId];
        snap.blockNumber = block.number;
        snap.totalSupply = totalSupply();
        
        // Record all holder balances at snapshot time
        for (uint256 i = 0; i < holders.length; i++) {
            address holder = holders[i];
            uint256 balance = balanceOf(holder);
            if (balance > 0) {
                snap.balances[holder] = balance;
                snap.hasBalance[holder] = true;
            }
        }
        
        emit SnapshotCreated(snapshotId, block.number);
    }
    
    function _snapshot() internal returns (uint256 snapshotId) {
        Layout storage l = _layout();
        
        snapshotId = ++l.currentSnapshotId;
        Snapshot storage snap = l.snapshots[snapshotId];
        snap.blockNumber = block.number;
        snap.totalSupply = totalSupply();
        
        emit SnapshotCreated(snapshotId, block.number);
    }
    
    /**
     * @notice Gets the balance of an account at a specific snapshot
     * @param account The address to query
     * @param snapshotId The snapshot ID
     * @return The balance at the snapshot
     */
    function balanceOfAt(address account, uint256 snapshotId) public view returns (uint256) {
        Layout storage l = _layout();
        Snapshot storage snap = l.snapshots[snapshotId];
        
        if (snap.blockNumber == 0) revert InvalidSnapshot();
        
        // If account had a balance recorded in this snapshot, return it
        if (snap.hasBalance[account]) {
            return snap.balances[account];
        }
        
        // Otherwise, search for the most recent snapshot before this one
        uint256[] storage accountSnapshots = l.accountSnapshotIds[account];
        for (uint256 i = accountSnapshots.length; i > 0; i--) {
            uint256 snapId = accountSnapshots[i - 1];
            if (snapId <= snapshotId && l.snapshots[snapId].hasBalance[account]) {
                return l.snapshots[snapId].balances[account];
            }
        }
        
        return 0;
    }
    
    /**
     * @notice Gets the total supply at a specific snapshot
     * @param snapshotId The snapshot ID
     * @return The total supply at the snapshot
     */
    function totalSupplyAt(uint256 snapshotId) public view returns (uint256) {
        Layout storage l = _layout();
        Snapshot storage snap = l.snapshots[snapshotId];
        
        if (snap.blockNumber == 0) revert InvalidSnapshot();
        return snap.totalSupply;
    }
    
    /**
     * @notice Gets all token holders at a specific snapshot
     * @param snapshotId The snapshot ID
     * @param holders Array of potential holders to check
     * @return addresses Array of addresses that had balances at the snapshot
     * @return balances Array of balances corresponding to the addresses
     */
    function holdersAt(uint256 snapshotId, address[] calldata holders) 
        public 
        view 
        returns (address[] memory addresses, uint256[] memory balances) 
    {
        uint256 count = 0;
        uint256[] memory tempBalances = new uint256[](holders.length);
        
        // Count holders with non-zero balances
        for (uint256 i = 0; i < holders.length; i++) {
            uint256 balance = balanceOfAt(holders[i], snapshotId);
            if (balance > 0) {
                tempBalances[count] = balance;
                count++;
            }
        }
        
        // Create correctly sized arrays
        addresses = new address[](count);
        balances = new uint256[](count);
        
        // Fill arrays
        uint256 index = 0;
        for (uint256 i = 0; i < holders.length; i++) {
            uint256 balance = balanceOfAt(holders[i], snapshotId);
            if (balance > 0) {
                addresses[index] = holders[i];
                balances[index] = balance;
                index++;
            }
        }
        
        return (addresses, balances);
    }
    
    /**
     * @notice Updates snapshot records when balance changes
     * @dev Called automatically on mint/burn/transfer
     */
    function _updateSnapshot(address account, uint256 newBalance) private {
        Layout storage l = _layout();
        uint256 currentId = l.currentSnapshotId;
        
        if (currentId == 0) return; // No snapshots yet
        
        Snapshot storage snap = l.snapshots[currentId];
        
        // Record this account's balance in the current snapshot if not already recorded
        if (!snap.hasBalance[account]) {
            snap.balances[account] = newBalance;
            snap.hasBalance[account] = true;
            
            // Track that this account has a balance in this snapshot
            l.accountSnapshotIds[account].push(currentId);
        }
    }

    /*────────── Modifiers ─────────*/
    modifier onlyTaskOrEdu() {
        _checkTaskOrEdu();
        _;
    }

    modifier onlyApprover() {
        _checkApprover();
        _;
    }

    modifier isMember() {
        _checkMember();
        _;
    }

    modifier onlyExecutor() {
        _checkExecutor();
        _;
    }

    function _checkTaskOrEdu() private view {
        Layout storage l = _layout();
        if (_msgSender() != l.executor && _msgSender() != l.taskManager && _msgSender() != l.educationHub) {
            revert NotTaskOrEdu();
        }
    }

    function _checkApprover() private view {
        Layout storage l = _layout();
        if (_msgSender() != l.executor && !_hasHat(_msgSender(), HatType.APPROVER)) {
            revert NotApprover();
        }
    }

    function _checkMember() private view {
        Layout storage l = _layout();
        if (_msgSender() != l.executor && !_hasHat(_msgSender(), HatType.MEMBER)) {
            revert NotMember();
        }
    }

    function _checkExecutor() private view {
        if (_msgSender() != _layout().executor) {
            revert Unauthorized();
        }
    }

    /*──────── Admin setters ───────*/
    function setTaskManager(address tm) external {
        if (tm == address(0)) revert InvalidAddress();
        Layout storage l = _layout();
        if (l.taskManager == address(0)) {
            l.taskManager = tm;
            emit TaskManagerSet(tm);
        } else {
            if (_msgSender() != l.executor) revert Unauthorized();
            l.taskManager = tm;
            emit TaskManagerSet(tm);
        }
    }

    function setEducationHub(address eh) external {
        if (eh == address(0)) revert InvalidAddress();
        Layout storage l = _layout();
        if (l.educationHub == address(0)) {
            l.educationHub = eh;
            emit EducationHubSet(eh);
        } else {
            if (_msgSender() != l.executor) revert Unauthorized();
            l.educationHub = eh;
            emit EducationHubSet(eh);
        }
    }

    function setMemberHatAllowed(uint256 h, bool ok) external onlyExecutor {
        Layout storage l = _layout();
        HatManager.setHatInArray(l.memberHatIds, h, ok);
        emit MemberHatSet(h, ok);
    }

    function setApproverHatAllowed(uint256 h, bool ok) external onlyExecutor {
        Layout storage l = _layout();
        HatManager.setHatInArray(l.approverHatIds, h, ok);
        emit ApproverHatSet(h, ok);
    }

    /*────── Mint by authorised modules ─────*/
    function mint(address to, uint256 amount) external nonReentrant onlyTaskOrEdu {
        if (to == address(0)) revert InvalidAddress();
        if (amount == 0) revert ZeroAmount();
        _mint(to, amount);
    }

    /*────────── Request flow ─────────*/
    function requestTokens(uint96 amount, string calldata ipfsHash) external isMember {
        if (amount == 0) revert ZeroAmount();
        if (bytes(ipfsHash).length == 0) revert ZeroAmount();

        Layout storage l = _layout();
        uint256 requestId = ++l.requestCounter;
        l.requests[requestId] = Request({requester: _msgSender(), amount: amount, approved: false, ipfsHash: ipfsHash});

        emit Requested(requestId, _msgSender(), amount, ipfsHash);
    }

    function approveRequest(uint256 id) external nonReentrant onlyApprover {
        Layout storage l = _layout();
        Request storage r = l.requests[id];
        if (r.requester == address(0)) revert RequestUnknown();
        if (r.approved) revert AlreadyApproved();
        if (r.requester == _msgSender()) revert NotRequester();

        r.approved = true;
        _mint(r.requester, r.amount);

        emit RequestApproved(id, _msgSender());
    }

    function cancelRequest(uint256 id) external nonReentrant {
        Layout storage l = _layout();
        Request storage r = l.requests[id];
        if (r.requester == address(0)) revert RequestUnknown();
        if (r.approved) revert AlreadyApproved();

        bool isApprover = (_msgSender() == l.executor) || _hasHat(_msgSender(), HatType.APPROVER);
        if (_msgSender() != r.requester && !isApprover) revert NotApprover();

        delete l.requests[id];
        emit RequestCancelled(id, _msgSender());
    }

    /*────── Transfer restrictions with snapshot updates ─────*/
    function transfer(address, uint256) public pure override returns (bool) {
        revert TransfersDisabled();
    }

    function approve(address, uint256) public pure override returns (bool) {
        revert TransfersDisabled();
    }

    function transferFrom(address, address, uint256) public pure override returns (bool) {
        revert TransfersDisabled();
    }

    /**
     * @dev Override _update to record snapshots on balance changes
     */
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) revert TransfersDisabled();
        
        // Update snapshots before balance change
        if (from != address(0)) {
            _updateSnapshot(from, balanceOf(from) - value);
        }
        if (to != address(0)) {
            _updateSnapshot(to, balanceOf(to) + value);
        }
        
        super._update(from, to, value);
    }

    /*───────── Internal Helper Functions ─────────*/
    function _hasHat(address user, HatType hatType) internal view returns (bool) {
        Layout storage l = _layout();
        uint256[] storage ids = hatType == HatType.MEMBER ? l.memberHatIds : l.approverHatIds;
        return HatManager.hasAnyHat(l.hats, ids, user);
    }

    /*───────── View helpers ─────────*/
    function requests(uint256 id)
        external
        view
        returns (address requester, uint96 amount, bool approved, string memory ipfsHash)
    {
        Layout storage l = _layout();
        Request storage r = l.requests[id];
        return (r.requester, r.amount, r.approved, r.ipfsHash);
    }

    function currentSnapshotId() external view returns (uint256) {
        return _layout().currentSnapshotId;
    }

    function taskManager() external view returns (address) {
        return _layout().taskManager;
    }

    function educationHub() external view returns (address) {
        return _layout().educationHub;
    }

    function hats() external view returns (IHats) {
        return _layout().hats;
    }

    function executor() external view returns (address) {
        return _layout().executor;
    }

    function requestCounter() external view returns (uint256) {
        return _layout().requestCounter;
    }

    function memberHatIds() external view returns (uint256[] memory) {
        return HatManager.getHatArray(_layout().memberHatIds);
    }

    function approverHatIds() external view returns (uint256[] memory) {
        return HatManager.getHatArray(_layout().approverHatIds);
    }

    function memberHatCount() external view returns (uint256) {
        return HatManager.getHatCount(_layout().memberHatIds);
    }

    function approverHatCount() external view returns (uint256) {
        return HatManager.getHatCount(_layout().approverHatIds);
    }

    function isMemberHat(uint256 hatId) external view returns (bool) {
        return HatManager.isHatInArray(_layout().memberHatIds, hatId);
    }

    function isApproverHat(uint256 hatId) external view returns (bool) {
        return HatManager.isHatInArray(_layout().approverHatIds, hatId);
    }
}