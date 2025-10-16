// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPaymaster} from "./interfaces/IPaymaster.sol";
import {IEntryPoint} from "./interfaces/IEntryPoint.sol";
import {PackedUserOperation, UserOpLib} from "./interfaces/PackedUserOperation.sol";
import {IHats} from "lib/hats-protocol/src/Interfaces/IHats.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import {IERC165} from "lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";

/**
 * @title PaymasterHub
 * @author POA Engineering
 * @notice Production-grade ERC-4337 paymaster with rule-driven policy, per-subject budgets, and optional inclusion bounty
 * @dev Implements ERC-7201 storage pattern with comprehensive security features
 * @custom:security-contact security@poa.org
 */
contract PaymasterHub is IPaymaster, ReentrancyGuard, IERC165 {
    using UserOpLib for bytes32;

    // ============ Custom Errors ============
    error EPOnly();
    error Paused();
    error NotAdmin();
    error NotOperator();
    error RuleDenied(address target, bytes4 selector);
    error FeeTooHigh();
    error GasTooHigh();
    error Ineligible();
    error BudgetExceeded();
    error InvalidRuleId();
    error PaymentFailed();
    error InvalidSubjectType();
    error InvalidVersion();
    error InvalidPaymasterData();
    error ZeroAddress();
    error InvalidEpochLength();
    error InvalidBountyConfig();
    error ContractNotDeployed();
    error ArrayLengthMismatch();

    // ============ Constants ============
    uint8 private constant PAYMASTER_DATA_VERSION = 1;
    uint8 private constant SUBJECT_TYPE_ACCOUNT = 0x00;
    uint8 private constant SUBJECT_TYPE_HAT = 0x01;

    uint32 private constant RULE_ID_GENERIC = 0x00000000;
    uint32 private constant RULE_ID_EXECUTOR = 0x00000001;
    uint32 private constant RULE_ID_COARSE = 0x000000FF;

    uint32 private constant MIN_EPOCH_LENGTH = 1 hours;
    uint32 private constant MAX_EPOCH_LENGTH = 365 days;
    uint256 private constant MAX_BOUNTY_PCT_BP = 10000; // 100%

    // ============ Events ============
    event PaymasterInitialized(address indexed entryPoint, address indexed hats, uint256 adminHatId);
    event RuleSet(address indexed target, bytes4 indexed selector, bool allowed, uint32 maxCallGasHint);
    event BudgetSet(bytes32 indexed subjectKey, uint128 capPerEpoch, uint32 epochLen, uint32 epochStart);
    event FeeCapsSet(
        uint256 maxFeePerGas,
        uint256 maxPriorityFeePerGas,
        uint32 maxCallGas,
        uint32 maxVerificationGas,
        uint32 maxPreVerificationGas
    );
    event PauseSet(bool paused);
    event OperatorHatSet(uint256 operatorHatId);
    event DepositIncrease(uint256 amount, uint256 newDeposit);
    event DepositWithdraw(address indexed to, uint256 amount);
    event BountyConfig(bool enabled, uint96 maxPerOp, uint16 pctBpCap);
    event BountyFunded(uint256 amount, uint256 newBalance);
    event BountySweep(address indexed to, uint256 amount);
    event BountyPaid(bytes32 indexed userOpHash, address indexed to, uint256 amount);
    event BountyPayFailed(bytes32 indexed userOpHash, address indexed to, uint256 amount);
    event UsageIncreased(bytes32 indexed subjectKey, uint256 delta, uint128 usedInEpoch, uint32 epochStart);
    event UserOpPosted(bytes32 indexed opHash, address indexed postedBy);
    event EmergencyWithdraw(address indexed to, uint256 amount);

    // ============ Immutables ============
    address public immutable ENTRY_POINT;

    // ============ Storage Structs ============
    struct Config {
        address hats;
        uint256 adminHatId;
        uint256 operatorHatId; // Optional role for budget/rule management
        bool paused;
        uint8 version;
        uint24 reserved; // For future use
    }

    struct FeeCaps {
        uint256 maxFeePerGas;
        uint256 maxPriorityFeePerGas;
        uint32 maxCallGas;
        uint32 maxVerificationGas;
        uint32 maxPreVerificationGas;
    }

    struct Rule {
        uint32 maxCallGasHint;
        bool allowed;
    }

    struct Budget {
        uint128 capPerEpoch; // Increased from uint64 for larger budgets
        uint128 usedInEpoch; // Increased from uint64
        uint32 epochLen;
        uint32 epochStart;
    }

    struct Bounty {
        bool enabled;
        uint96 maxBountyWeiPerOp;
        uint16 pctBpCap;
        uint144 totalPaid; // Track total bounties paid
    }

    // ============ ERC-7201 Storage Locations ============
    // keccak256(abi.encode(uint256(keccak256("poa.paymasterhub.config")) - 1))
    bytes32 private constant CONFIG_STORAGE_LOCATION =
        0xabfaccef10a57a6be41f1fbc4a8a7f1b6e210db05ae07b44b3a1bb95e2c7978e;

    // keccak256(abi.encode(uint256(keccak256("poa.paymasterhub.feeCaps")) - 1))
    bytes32 private constant FEECAPS_STORAGE_LOCATION =
        0x31c1f70de237698620907d8a0468bf5356fb50f4719bfcd111876a981cbccb5c;

    // keccak256(abi.encode(uint256(keccak256("poa.paymasterhub.rules")) - 1))
    bytes32 private constant RULES_STORAGE_LOCATION =
        0xbe2280b3d3247ad137be1f9de7cbb32fc261644cda199a3a24b0a06528ef326f;

    // keccak256(abi.encode(uint256(keccak256("poa.paymasterhub.budgets")) - 1))
    bytes32 private constant BUDGETS_STORAGE_LOCATION =
        0xf14d4c678226f6697d18c9cd634533b58566936459364e55f23c57845d71389e;

    // keccak256(abi.encode(uint256(keccak256("poa.paymasterhub.bounty")) - 1))
    bytes32 private constant BOUNTY_STORAGE_LOCATION =
        0x5aefd14c2f5001261e819816e3c40d9d9cc763af84e5df87cd5955f0f5cfd09e;

    // ============ Constructor ============
    constructor(address _entryPoint, address _hats, uint256 _adminHatId) {
        if (_entryPoint == address(0)) revert ZeroAddress();
        if (_hats == address(0)) revert ZeroAddress();
        if (_adminHatId == 0) revert ZeroAddress();

        // Verify entryPoint is a contract
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(_entryPoint)
        }
        if (codeSize == 0) revert ContractNotDeployed();

        ENTRY_POINT = _entryPoint;

        Config storage config = _getConfigStorage();
        config.hats = _hats;
        config.adminHatId = _adminHatId;
        config.version = PAYMASTER_DATA_VERSION;
        config.paused = false;

        emit PaymasterInitialized(_entryPoint, _hats, _adminHatId);
    }

    // ============ Modifiers ============
    modifier onlyEntryPoint() {
        if (msg.sender != ENTRY_POINT) revert EPOnly();
        _;
    }

    modifier onlyAdmin() {
        Config storage config = _getConfigStorage();
        if (!IHats(config.hats).isWearerOfHat(msg.sender, config.adminHatId)) {
            revert NotAdmin();
        }
        _;
    }

    modifier onlyOperator() {
        Config storage config = _getConfigStorage();
        bool isAdmin = IHats(config.hats).isWearerOfHat(msg.sender, config.adminHatId);
        bool isOperator =
            config.operatorHatId != 0 && IHats(config.hats).isWearerOfHat(msg.sender, config.operatorHatId);
        if (!isAdmin && !isOperator) revert NotOperator();
        _;
    }

    modifier whenNotPaused() {
        if (_getConfigStorage().paused) revert Paused();
        _;
    }

    // ============ ERC-165 Support ============
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IPaymaster).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    // ============ ERC-4337 Paymaster Functions ============

    /**
     * @notice Validates a UserOperation for sponsorship
     * @dev Called by EntryPoint during simulation and execution
     * @param userOp The user operation to validate
     * @param userOpHash Hash of the user operation
     * @param maxCost Maximum cost that will be reimbursed
     * @return context Encoded context for postOp
     * @return validationData Packed validation data (sigFailed, validUntil, validAfter)
     */
    function validatePaymasterUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 maxCost)
        external
        override
        onlyEntryPoint
        whenNotPaused
        returns (bytes memory context, uint256 validationData)
    {
        // Decode and validate paymasterAndData
        (uint8 version, uint8 subjectType, bytes20 subjectId, uint32 ruleId, uint64 mailboxCommit8) =
            _decodePaymasterData(userOp.paymasterAndData);

        if (version != PAYMASTER_DATA_VERSION) revert InvalidVersion();

        // Validate subject eligibility
        bytes32 subjectKey = _validateSubjectEligibility(userOp.sender, subjectType, subjectId);

        // Validate target/selector rules
        _validateRules(userOp, ruleId);

        // Validate fee and gas caps
        _validateFeeCaps(userOp);

        // Check and update budget
        uint32 currentEpochStart = _checkBudget(subjectKey, maxCost);

        // Prepare context for postOp
        context = abi.encode(subjectKey, currentEpochStart, userOpHash, mailboxCommit8, uint160(tx.origin));

        // Return 0 for no signature failure and no time restrictions
        validationData = 0;
    }

    /**
     * @notice Post-operation hook called after UserOperation execution
     * @dev Updates budget usage and processes bounties
     * @param mode Execution mode (success/revert/postOpRevert)
     * @param context Context from validatePaymasterUserOp
     * @param actualGasCost Actual gas cost to be reimbursed
     */
    function postOp(IPaymaster.PostOpMode mode, bytes calldata context, uint256 actualGasCost)
        external
        override
        onlyEntryPoint
        nonReentrant
    {
        (bytes32 subjectKey, uint32 epochStart, bytes32 userOpHash, uint64 mailboxCommit8, address bundlerOrigin) =
            abi.decode(context, (bytes32, uint32, bytes32, uint64, address));

        // Update usage regardless of execution mode
        _updateUsage(subjectKey, epochStart, actualGasCost);

        // Process bounty only on successful execution
        if (mode == IPaymaster.PostOpMode.opSucceeded && mailboxCommit8 != 0) {
            _processBounty(userOpHash, bundlerOrigin, actualGasCost);
        }
    }

    // ============ Admin Functions ============

    /**
     * @notice Set a rule for target/selector combination
     * @dev Only callable by admin or operator
     */
    function setRule(address target, bytes4 selector, bool allowed, uint32 maxCallGasHint) external onlyOperator {
        if (target == address(0)) revert ZeroAddress();

        mapping(address => mapping(bytes4 => Rule)) storage rules = _getRulesStorage();
        rules[target][selector] = Rule({allowed: allowed, maxCallGasHint: maxCallGasHint});
        emit RuleSet(target, selector, allowed, maxCallGasHint);
    }

    /**
     * @notice Batch set rules for multiple target/selector combinations
     */
    function setRulesBatch(
        address[] calldata targets,
        bytes4[] calldata selectors,
        bool[] calldata allowed,
        uint32[] calldata maxCallGasHints
    ) external onlyOperator {
        uint256 length = targets.length;
        if (length != selectors.length || length != allowed.length || length != maxCallGasHints.length) {
            revert ArrayLengthMismatch();
        }

        mapping(address => mapping(bytes4 => Rule)) storage rules = _getRulesStorage();

        for (uint256 i; i < length;) {
            if (targets[i] == address(0)) revert ZeroAddress();

            rules[targets[i]][selectors[i]] = Rule({allowed: allowed[i], maxCallGasHint: maxCallGasHints[i]});

            emit RuleSet(targets[i], selectors[i], allowed[i], maxCallGasHints[i]);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Clear a rule for target/selector combination
     */
    function clearRule(address target, bytes4 selector) external onlyOperator {
        mapping(address => mapping(bytes4 => Rule)) storage rules = _getRulesStorage();
        delete rules[target][selector];
        emit RuleSet(target, selector, false, 0);
    }

    /**
     * @notice Set budget for a subject
     * @dev Validates epoch length and initializes epoch start
     */
    function setBudget(bytes32 subjectKey, uint128 capPerEpoch, uint32 epochLen) external onlyOperator {
        if (epochLen < MIN_EPOCH_LENGTH || epochLen > MAX_EPOCH_LENGTH) {
            revert InvalidEpochLength();
        }

        mapping(bytes32 => Budget) storage budgets = _getBudgetsStorage();
        Budget storage budget = budgets[subjectKey];

        // If changing epoch length, reset usage
        if (budget.epochLen != epochLen && budget.epochLen != 0) {
            budget.usedInEpoch = 0;
        }

        budget.capPerEpoch = capPerEpoch;
        budget.epochLen = epochLen;

        // Initialize epoch start if not set
        if (budget.epochStart == 0) {
            budget.epochStart = uint32(block.timestamp);
        }

        emit BudgetSet(subjectKey, capPerEpoch, epochLen, budget.epochStart);
    }

    /**
     * @notice Manually set epoch start for a subject
     */
    function setEpochStart(bytes32 subjectKey, uint32 epochStart) external onlyOperator {
        mapping(bytes32 => Budget) storage budgets = _getBudgetsStorage();
        Budget storage budget = budgets[subjectKey];

        budget.epochStart = epochStart;
        budget.usedInEpoch = 0; // Reset usage when manually setting epoch

        emit BudgetSet(subjectKey, budget.capPerEpoch, budget.epochLen, epochStart);
    }

    /**
     * @notice Set fee and gas caps
     */
    function setFeeCaps(
        uint256 maxFeePerGas,
        uint256 maxPriorityFeePerGas,
        uint32 maxCallGas,
        uint32 maxVerificationGas,
        uint32 maxPreVerificationGas
    ) external onlyOperator {
        FeeCaps storage feeCaps = _getFeeCapsStorage();

        feeCaps.maxFeePerGas = maxFeePerGas;
        feeCaps.maxPriorityFeePerGas = maxPriorityFeePerGas;
        feeCaps.maxCallGas = maxCallGas;
        feeCaps.maxVerificationGas = maxVerificationGas;
        feeCaps.maxPreVerificationGas = maxPreVerificationGas;

        emit FeeCapsSet(maxFeePerGas, maxPriorityFeePerGas, maxCallGas, maxVerificationGas, maxPreVerificationGas);
    }

    /**
     * @notice Pause or unpause the paymaster
     * @dev Only admin can pause/unpause
     */
    function setPause(bool paused) external onlyAdmin {
        _getConfigStorage().paused = paused;
        emit PauseSet(paused);
    }

    /**
     * @notice Set optional operator hat for delegated management
     */
    function setOperatorHat(uint256 operatorHatId) external onlyAdmin {
        _getConfigStorage().operatorHatId = operatorHatId;
        emit OperatorHatSet(operatorHatId);
    }

    /**
     * @notice Configure bounty parameters
     */
    function setBounty(bool enabled, uint96 maxBountyWeiPerOp, uint16 pctBpCap) external onlyAdmin {
        if (pctBpCap > MAX_BOUNTY_PCT_BP) revert InvalidBountyConfig();

        (Bounty storage bounty,) = _getBountyStorage();
        bounty.enabled = enabled;
        bounty.maxBountyWeiPerOp = maxBountyWeiPerOp;
        bounty.pctBpCap = pctBpCap;

        emit BountyConfig(enabled, maxBountyWeiPerOp, pctBpCap);
    }

    /**
     * @notice Deposit funds to EntryPoint for gas reimbursement
     */
    function depositToEntryPoint() external payable onlyOperator {
        IEntryPoint(ENTRY_POINT).depositTo{value: msg.value}(address(this));

        uint256 newDeposit = IEntryPoint(ENTRY_POINT).balanceOf(address(this));
        emit DepositIncrease(msg.value, newDeposit);
    }

    /**
     * @notice Withdraw funds from EntryPoint deposit
     */
    function withdrawFromEntryPoint(address payable to, uint256 amount) external onlyAdmin {
        if (to == address(0)) revert ZeroAddress();

        IEntryPoint(ENTRY_POINT).withdrawTo(to, amount);
        emit DepositWithdraw(to, amount);
    }

    /**
     * @notice Fund bounty pool (contract balance)
     */
    function fundBounty() external payable {
        emit BountyFunded(msg.value, address(this).balance);
    }

    /**
     * @notice Withdraw from bounty pool
     */
    function sweepBounty(address payable to, uint256 amount) external onlyAdmin {
        if (to == address(0)) revert ZeroAddress();
        if (amount > address(this).balance) revert PaymentFailed();

        (bool success,) = to.call{value: amount}("");
        if (!success) revert PaymentFailed();

        emit BountySweep(to, amount);
    }

    /**
     * @notice Emergency withdrawal in case of critical issues
     */
    function emergencyWithdraw(address payable to) external onlyAdmin {
        if (to == address(0)) revert ZeroAddress();

        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success,) = to.call{value: balance}("");
            if (!success) revert PaymentFailed();
        }

        emit EmergencyWithdraw(to, balance);
    }

    // ============ Mailbox Function ============

    /**
     * @notice Post a UserOperation to the on-chain mailbox
     * @param packedUserOp The packed user operation data
     * @return opHash Hash of the posted operation
     */
    function postUserOp(bytes calldata packedUserOp) external returns (bytes32 opHash) {
        opHash = keccak256(packedUserOp);
        emit UserOpPosted(opHash, msg.sender);
    }

    // ============ Storage Getters (for Lens) ============

    /**
     * @notice Get the current configuration
     * @return The Config struct
     */
    function getConfig() external view returns (Config memory) {
        return _getConfigStorage();
    }

    /**
     * @notice Get budget for a specific subject
     * @param key The subject key (user, role, or org)
     * @return The Budget struct
     */
    function getBudget(bytes32 key) external view returns (Budget memory) {
        return _getBudgetsStorage()[key];
    }

    /**
     * @notice Get rule for a specific target and selector
     * @param target The target contract address
     * @param selector The function selector
     * @return The Rule struct
     */
    function getRule(address target, bytes4 selector) external view returns (Rule memory) {
        return _getRulesStorage()[target][selector];
    }

    /**
     * @notice Get the current fee caps
     * @return The FeeCaps struct
     */
    function getFeeCaps() external view returns (FeeCaps memory) {
        return _getFeeCapsStorage();
    }

    /**
     * @notice Get the bounty configuration
     * @return The Bounty struct
     */
    function getBountyConfig() external view returns (Bounty memory) {
        (Bounty storage b,) = _getBountyStorage();
        return b;
    }

    // ============ Storage Accessors ============
    function _getConfigStorage() private pure returns (Config storage $) {
        assembly {
            $.slot := CONFIG_STORAGE_LOCATION
        }
    }

    function _getFeeCapsStorage() private pure returns (FeeCaps storage $) {
        assembly {
            $.slot := FEECAPS_STORAGE_LOCATION
        }
    }

    function _getRulesStorage() private pure returns (mapping(address => mapping(bytes4 => Rule)) storage $) {
        assembly {
            $.slot := RULES_STORAGE_LOCATION
        }
    }

    function _getBudgetsStorage() private pure returns (mapping(bytes32 => Budget) storage $) {
        assembly {
            $.slot := BUDGETS_STORAGE_LOCATION
        }
    }

    function _getBountyStorage()
        private
        pure
        returns (Bounty storage bounty, mapping(bytes32 => bool) storage paidOnce)
    {
        assembly {
            bounty.slot := BOUNTY_STORAGE_LOCATION
            mstore(0x00, BOUNTY_STORAGE_LOCATION)
            paidOnce.slot := add(keccak256(0x00, 0x20), 1)
        }
    }

    // ============ Internal Functions ============

    function _decodePaymasterData(bytes calldata paymasterAndData)
        private
        pure
        returns (uint8 version, uint8 subjectType, bytes20 subjectId, uint32 ruleId, uint64 mailboxCommit8)
    {
        if (paymasterAndData.length < 54) revert InvalidPaymasterData();

        // Skip first 20 bytes (paymaster address) and decode the rest
        version = uint8(paymasterAndData[20]);
        subjectType = uint8(paymasterAndData[21]);

        // Extract bytes20 subjectId from bytes 22-41
        assembly {
            subjectId := calldataload(add(paymasterAndData.offset, 22))
        }

        // Extract ruleId from bytes 42-45
        ruleId = uint32(bytes4(paymasterAndData[42:46]));

        // Extract mailboxCommit8 from bytes 46-53
        mailboxCommit8 = uint64(bytes8(paymasterAndData[46:54]));
    }

    function _validateSubjectEligibility(address sender, uint8 subjectType, bytes20 subjectId)
        private
        view
        returns (bytes32 subjectKey)
    {
        if (subjectType == SUBJECT_TYPE_ACCOUNT) {
            if (address(subjectId) != sender) revert Ineligible();
            subjectKey = keccak256(abi.encodePacked(subjectType, subjectId));
        } else if (subjectType == SUBJECT_TYPE_HAT) {
            uint256 hatId = uint256(uint160(subjectId));
            if (!IHats(_getConfigStorage().hats).isWearerOfHat(sender, hatId)) {
                revert Ineligible();
            }
            subjectKey = keccak256(abi.encodePacked(subjectType, subjectId));
        } else {
            revert InvalidSubjectType();
        }
    }

    function _validateRules(PackedUserOperation calldata userOp, uint32 ruleId) private view {
        (address target, bytes4 selector) = _extractTargetSelector(userOp, ruleId);

        mapping(address => mapping(bytes4 => Rule)) storage rules = _getRulesStorage();
        Rule storage rule = rules[target][selector];

        if (!rule.allowed) revert RuleDenied(target, selector);

        // Check gas hint if set
        if (rule.maxCallGasHint > 0) {
            (, uint128 callGasLimit) = UserOpLib.unpackAccountGasLimits(userOp.accountGasLimits);
            if (callGasLimit > rule.maxCallGasHint) revert GasTooHigh();
        }
    }

    function _extractTargetSelector(PackedUserOperation calldata userOp, uint32 ruleId)
        private
        pure
        returns (address target, bytes4 selector)
    {
        bytes calldata callData = userOp.callData;

        if (callData.length < 4) revert InvalidPaymasterData();

        if (ruleId == RULE_ID_GENERIC) {
            // SimpleAccount.execute pattern
            selector = bytes4(callData[0:4]);

            // Check for execute(address,uint256,bytes)
            if (selector == 0xb61d27f6 && callData.length >= 0x64) {
                assembly {
                    target := calldataload(add(callData.offset, 0x04))
                    let dataOffset := calldataload(add(callData.offset, 0x44))
                    if lt(add(dataOffset, 0x64), callData.length) {
                        selector := calldataload(add(add(callData.offset, 0x64), dataOffset))
                    }
                }
                selector = bytes4(selector);
            }
            // Check for executeBatch
            else if (selector == 0x18dfb3c7) {
                target = userOp.sender;
            } else {
                target = userOp.sender;
            }
        } else if (ruleId == RULE_ID_EXECUTOR) {
            // Custom Executor pattern
            target = userOp.sender;
            selector = bytes4(callData[0:4]);
        } else if (ruleId == RULE_ID_COARSE) {
            // Coarse mode: only check account's selector
            target = userOp.sender;
            selector = bytes4(callData[0:4]);
        } else {
            revert InvalidRuleId();
        }
    }

    function _validateFeeCaps(PackedUserOperation calldata userOp) private view {
        FeeCaps storage caps = _getFeeCapsStorage();

        if (caps.maxFeePerGas > 0 && userOp.maxFeePerGas > caps.maxFeePerGas) {
            revert FeeTooHigh();
        }
        if (caps.maxPriorityFeePerGas > 0 && userOp.maxPriorityFeePerGas > caps.maxPriorityFeePerGas) {
            revert FeeTooHigh();
        }

        (uint128 verificationGasLimit, uint128 callGasLimit) = UserOpLib.unpackAccountGasLimits(userOp.accountGasLimits);

        if (caps.maxCallGas > 0 && callGasLimit > caps.maxCallGas) {
            revert GasTooHigh();
        }
        if (caps.maxVerificationGas > 0 && verificationGasLimit > caps.maxVerificationGas) {
            revert GasTooHigh();
        }
        if (caps.maxPreVerificationGas > 0 && userOp.preVerificationGas > caps.maxPreVerificationGas) {
            revert GasTooHigh();
        }
    }

    function _checkBudget(bytes32 subjectKey, uint256 maxCost) private returns (uint32 currentEpochStart) {
        mapping(bytes32 => Budget) storage budgets = _getBudgetsStorage();
        Budget storage budget = budgets[subjectKey];

        // Check if epoch needs rolling
        uint256 currentTime = block.timestamp;
        if (budget.epochLen > 0 && currentTime >= budget.epochStart + budget.epochLen) {
            // Calculate number of complete epochs passed
            uint32 epochsPassed = uint32((currentTime - budget.epochStart) / budget.epochLen);
            budget.epochStart = budget.epochStart + (epochsPassed * budget.epochLen);
            budget.usedInEpoch = 0;
        }

        // Check budget capacity (safe conversion as maxCost is bounded by EntryPoint)
        if (budget.usedInEpoch + uint128(maxCost) > budget.capPerEpoch) {
            revert BudgetExceeded();
        }

        currentEpochStart = budget.epochStart;
    }

    function _updateUsage(bytes32 subjectKey, uint32 epochStart, uint256 actualGasCost) private {
        mapping(bytes32 => Budget) storage budgets = _getBudgetsStorage();
        Budget storage budget = budgets[subjectKey];

        // Only update if we're still in the same epoch
        if (budget.epochStart == epochStart) {
            // Safe to cast as actualGasCost is bounded
            uint128 cost = uint128(actualGasCost);
            budget.usedInEpoch += cost;
            emit UsageIncreased(subjectKey, actualGasCost, budget.usedInEpoch, epochStart);
        }
    }

    function _processBounty(bytes32 userOpHash, address bundlerOrigin, uint256 actualGasCost) private {
        (Bounty storage bounty, mapping(bytes32 => bool) storage paidOnce) = _getBountyStorage();

        if (!bounty.enabled) return;
        if (paidOnce[userOpHash]) return;

        paidOnce[userOpHash] = true;

        // Calculate tip amount
        uint256 tip = bounty.maxBountyWeiPerOp;
        if (bounty.pctBpCap > 0) {
            uint256 pctTip = (actualGasCost * bounty.pctBpCap) / 10000;
            if (pctTip < tip) {
                tip = pctTip;
            }
        }

        // Ensure we have sufficient balance
        if (tip > address(this).balance) {
            tip = address(this).balance;
        }

        if (tip > 0) {
            // Update total paid
            bounty.totalPaid += uint144(tip);

            // Attempt payment with gas limit
            (bool success,) = bundlerOrigin.call{value: tip, gas: 30000}("");

            if (success) {
                emit BountyPaid(userOpHash, bundlerOrigin, tip);
            } else {
                emit BountyPayFailed(userOpHash, bundlerOrigin, tip);
            }
        }
    }

    // ============ Receive Function ============
    receive() external payable {
        emit BountyFunded(msg.value, address(this).balance);
    }
}
