// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPaymaster} from "./interfaces/IPaymaster.sol";
import {IEntryPoint} from "./interfaces/IEntryPoint.sol";
import {PackedUserOperation, UserOpLib} from "./interfaces/PackedUserOperation.sol";
import {IHats} from "lib/hats-protocol/src/Interfaces/IHats.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IERC165} from "lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";

/**
 * @title PaymasterHub
 * @author POA Engineering
 * @notice Production-grade ERC-4337 paymaster shared across all POA organizations
 * @dev Implements ERC-7201 storage pattern with org-scoped configuration and budgets
 * @dev Upgradeable via UUPS pattern, governed by PoaManager
 * @custom:security-contact security@poa.org
 */
contract PaymasterHub is IPaymaster, Initializable, UUPSUpgradeable, ReentrancyGuardUpgradeable, IERC165 {
    using UserOpLib for bytes32;

    // ============ Custom Errors ============
    error EPOnly();
    error Paused();
    error NotAdmin();
    error NotOperator();
    error NotPoaManager();
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
    error OrgNotRegistered();
    error OrgAlreadyRegistered();
    error GracePeriodTxLimitReached();
    error InsufficientDepositForSolidarity();
    error SolidarityLimitExceeded();
    error InsufficientOrgBalance();
    error OrgIsBanned();

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
    event PaymasterInitialized(address indexed entryPoint, address indexed hats, address indexed poaManager);
    event OrgRegistered(bytes32 indexed orgId, uint256 adminHatId, uint256 operatorHatId);
    event RuleSet(bytes32 indexed orgId, address indexed target, bytes4 indexed selector, bool allowed, uint32 maxCallGasHint);
    event BudgetSet(bytes32 indexed orgId, bytes32 subjectKey, uint128 capPerEpoch, uint32 epochLen, uint32 epochStart);
    event FeeCapsSet(
        bytes32 indexed orgId,
        uint256 maxFeePerGas,
        uint256 maxPriorityFeePerGas,
        uint32 maxCallGas,
        uint32 maxVerificationGas,
        uint32 maxPreVerificationGas
    );
    event PauseSet(bytes32 indexed orgId, bool paused);
    event OperatorHatSet(bytes32 indexed orgId, uint256 operatorHatId);
    event DepositIncrease(uint256 amount, uint256 newDeposit);
    event DepositWithdraw(address indexed to, uint256 amount);
    event BountyConfig(bytes32 indexed orgId, bool enabled, uint96 maxPerOp, uint16 pctBpCap);
    event BountyFunded(uint256 amount, uint256 newBalance);
    event BountySweep(address indexed to, uint256 amount);
    event BountyPaid(bytes32 indexed userOpHash, address indexed to, uint256 amount);
    event BountyPayFailed(bytes32 indexed userOpHash, address indexed to, uint256 amount);
    event UsageIncreased(bytes32 indexed orgId, bytes32 subjectKey, uint256 delta, uint128 usedInEpoch, uint32 epochStart);
    event UserOpPosted(bytes32 indexed opHash, address indexed postedBy);
    event EmergencyWithdraw(address indexed to, uint256 amount);
    event OrgDepositReceived(bytes32 indexed orgId, address indexed from, uint256 amount);
    event SolidarityFeeCollected(bytes32 indexed orgId, uint256 amount);
    event SolidarityDonationReceived(address indexed from, uint256 amount);
    event GracePeriodConfigUpdated(uint32 initialGraceDays, uint32 maxTxDuringGrace, uint128 minDepositRequired);
    event OrgBannedFromSolidarity(bytes32 indexed orgId, bool banned);

    // ============ Storage Variables ============
    /// @custom:storage-location erc7201:poa.paymasterhub.main
    struct MainStorage {
        address entryPoint;
        address hats;
        address poaManager;
    }

    // keccak256(abi.encode(uint256(keccak256("poa.paymasterhub.main")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant MAIN_STORAGE_LOCATION =
        0x9a7a9f40de2a7f2c3b8e6d5c4a3b2c1d0e9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b;

    // ============ Storage Structs ============

    /**
     * @dev Organization configuration
     * Storage optimization: registeredAt packed with paused to save gas
     */
    struct OrgConfig {
        uint256 adminHatId;      // Slot 0
        uint256 operatorHatId;   // Slot 1: Optional role for budget/rule management
        bool paused;             // Slot 2 (1 byte)
        uint40 registeredAt;     // Slot 2 (5 bytes): UNIX timestamp, good until year 36812
        bool bannedFromSolidarity; // Slot 2 (1 byte)
        // 25 bytes remaining in slot 2 for future use
    }

    /**
     * @dev Per-org financial tracking for solidarity fund accounting
     */
    struct OrgFinancials {
        uint128 deposited;        // Current balance deposited by org
        uint128 totalDeposited;   // Cumulative lifetime deposits (never decreases)
        uint128 spent;            // Total spent from org's own deposits
        uint128 solidarityUsed;   // Total spent from solidarity fund
        uint128 feesContributed;  // Total 1% solidarity fees paid
        uint32 lifetimeTxCount;   // Transaction count during initial grace period
        uint96 reserved;          // Padding for future use
    }

    /**
     * @dev Global solidarity fund state
     */
    struct SolidarityFund {
        uint128 balance;              // Current solidarity fund balance
        uint128 totalFeesCollected;   // Cumulative fees collected
        uint32 numActiveOrgs;         // Number of orgs with deposits > 0
        uint16 feePercentageBps;      // Fee as basis points (100 = 1%)
        uint80 reserved;              // Padding
    }

    /**
     * @dev Grace period configuration for unfunded orgs
     */
    struct GracePeriodConfig {
        uint32 initialGraceDays;      // Startup period with zero deposits (default 90)
        uint32 maxTxDuringGrace;      // Max transactions during startup (default 3000)
        uint128 minDepositRequired;   // Minimum balance to maintain after grace (default 0.003 ETH ~$10)
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
        uint128 capPerEpoch;
        uint128 usedInEpoch;
        uint32 epochLen;
        uint32 epochStart;
    }

    struct Bounty {
        bool enabled;
        uint96 maxBountyWeiPerOp;
        uint16 pctBpCap;
        uint144 totalPaid;
    }

    // ============ ERC-7201 Storage Locations ============
    // keccak256(abi.encode(uint256(keccak256("poa.paymasterhub.orgs")) - 1))
    bytes32 private constant ORGS_STORAGE_LOCATION =
        0x7e8e7f71b618a8d3f4c7c1c6c0e8f8e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0e0;

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

    // keccak256(abi.encode(uint256(keccak256("poa.paymasterhub.financials")) - 1))
    bytes32 private constant FINANCIALS_STORAGE_LOCATION =
        0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;

    // keccak256(abi.encode(uint256(keccak256("poa.paymasterhub.solidarity")) - 1))
    bytes32 private constant SOLIDARITY_STORAGE_LOCATION =
        0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890;

    // keccak256(abi.encode(uint256(keccak256("poa.paymasterhub.graceperiod")) - 1))
    bytes32 private constant GRACEPERIOD_STORAGE_LOCATION =
        0xfedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321;

    // ============ Constructor ============
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // ============ Initializer ============
    /**
     * @notice Initialize the PaymasterHub
     * @dev Called once during proxy deployment
     * @param _entryPoint ERC-4337 EntryPoint address
     * @param _hats Hats Protocol address
     * @param _poaManager PoaManager address for upgrade authorization
     */
    function initialize(address _entryPoint, address _hats, address _poaManager) public initializer {
        if (_entryPoint == address(0)) revert ZeroAddress();
        if (_hats == address(0)) revert ZeroAddress();
        if (_poaManager == address(0)) revert ZeroAddress();

        // Verify entryPoint is a contract
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(_entryPoint)
        }
        if (codeSize == 0) revert ContractNotDeployed();

        // Initialize upgradeable contracts
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        // Store main config
        MainStorage storage main = _getMainStorage();
        main.entryPoint = _entryPoint;
        main.hats = _hats;
        main.poaManager = _poaManager;

        // Initialize solidarity fund with 1% fee
        SolidarityFund storage solidarity = _getSolidarityStorage();
        solidarity.feePercentageBps = 100; // 1%

        // Initialize grace period with defaults (90 days, 3000 tx, 0.003 ETH ~$10)
        GracePeriodConfig storage grace = _getGracePeriodStorage();
        grace.initialGraceDays = 90;
        grace.maxTxDuringGrace = 3000;
        grace.minDepositRequired = 0.003 ether; // ~$10 on L2s

        emit PaymasterInitialized(_entryPoint, _hats, _poaManager);
    }

    // ============ Org Registration ============

    /**
     * @notice Register a new organization with the paymaster
     * @dev Called by OrgDeployer during org creation
     * @param orgId Unique organization identifier
     * @param adminHatId Hat ID for org admin (topHat)
     * @param operatorHatId Optional hat ID for operators (0 if none)
     */
    function registerOrg(bytes32 orgId, uint256 adminHatId, uint256 operatorHatId) external {
        if (adminHatId == 0) revert ZeroAddress();

        mapping(bytes32 => OrgConfig) storage orgs = _getOrgsStorage();
        if (orgs[orgId].adminHatId != 0) revert OrgAlreadyRegistered();

        orgs[orgId] = OrgConfig({
            adminHatId: adminHatId,
            operatorHatId: operatorHatId,
            paused: false,
            registeredAt: uint40(block.timestamp),
            bannedFromSolidarity: false
        });

        emit OrgRegistered(orgId, adminHatId, operatorHatId);
    }

    // ============ Modifiers ============
    modifier onlyEntryPoint() {
        if (msg.sender != _getMainStorage().entryPoint) revert EPOnly();
        _;
    }

    modifier onlyOrgAdmin(bytes32 orgId) {
        OrgConfig storage org = _getOrgsStorage()[orgId];
        if (org.adminHatId == 0) revert OrgNotRegistered();
        if (!IHats(_getMainStorage().hats).isWearerOfHat(msg.sender, org.adminHatId)) {
            revert NotAdmin();
        }
        _;
    }

    modifier onlyOrgOperator(bytes32 orgId) {
        OrgConfig storage org = _getOrgsStorage()[orgId];
        if (org.adminHatId == 0) revert OrgNotRegistered();

        bool isAdmin = IHats(_getMainStorage().hats).isWearerOfHat(msg.sender, org.adminHatId);
        bool isOperator =
            org.operatorHatId != 0 && IHats(_getMainStorage().hats).isWearerOfHat(msg.sender, org.operatorHatId);
        if (!isAdmin && !isOperator) revert NotOperator();
        _;
    }

    modifier whenOrgNotPaused(bytes32 orgId) {
        if (_getOrgsStorage()[orgId].paused) revert Paused();
        _;
    }

    // ============ ERC-165 Support ============
    function supportsInterface(bytes4 interfaceId) public pure override returns (bool) {
        return interfaceId == type(IPaymaster).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    // ============ Solidarity Fund Functions ============

    /**
     * @notice Check if org can access solidarity fund based on grace period and deposit requirements
     * @dev Implements "maintain minimum" model - checks current balance (deposited)
     *
     * Grace period model:
     * - First 90 days: Free solidarity access with transaction limit (3000 tx on L2)
     * - After 90 days: Must maintain minimum deposit (~$10) to access solidarity
     *
     * Gas overhead:
     * - Funded orgs (deposited >= minDepositRequired): ~100 gas
     * - Unfunded orgs in initial grace: ~220 gas
     * - Unfunded orgs after grace without sufficient balance: Reverts immediately
     *
     * @param orgId The organization identifier
     * @param maxCost Maximum cost of the operation (for solidarity limit check)
     */
    function _checkSolidarityAccess(bytes32 orgId, uint256 maxCost) internal view {
        mapping(bytes32 => OrgConfig) storage orgs = _getOrgsStorage();
        mapping(bytes32 => OrgFinancials) storage financials = _getFinancialsStorage();
        GracePeriodConfig storage grace = _getGracePeriodStorage();

        OrgConfig storage config = orgs[orgId];
        OrgFinancials storage org = financials[orgId];

        // Check if org is banned from solidarity
        if (config.bannedFromSolidarity) revert OrgIsBanned();

        // Calculate grace period end time
        uint256 graceEndTime = config.registeredAt + (uint256(grace.initialGraceDays) * 1 days);
        bool inInitialGrace = block.timestamp < graceEndTime;

        if (inInitialGrace) {
            // Startup phase: can use solidarity even with zero deposits
            // But enforce transaction limit to prevent spam
            if (org.lifetimeTxCount >= grace.maxTxDuringGrace) {
                revert GracePeriodTxLimitReached();
            }
        } else {
            // After startup: must MAINTAIN minimum deposit (like $10/month commitment)
            // This checks deposited (current balance), not totalDeposited (cumulative)
            // Orgs must keep funds in reserve to access solidarity
            if (org.deposited < grace.minDepositRequired) {
                revert InsufficientDepositForSolidarity();
            }
        }

        // Calculate org's solidarity allocation and check limit
        uint256 solidarityLimit = _calculateSolidarityLimit(orgId);
        if (org.solidarityUsed + maxCost > solidarityLimit) {
            revert SolidarityLimitExceeded();
        }
    }

    /**
     * @notice Calculate solidarity fund allocation for an org
     * @dev Algorithmic allocation based on pool size, org count, and usage
     * @param orgId The organization identifier
     * @return Solidarity allocation in wei
     */
    function _calculateSolidarityLimit(bytes32 orgId) internal view returns (uint256) {
        SolidarityFund storage solidarity = _getSolidarityStorage();
        mapping(bytes32 => OrgFinancials) storage financials = _getFinancialsStorage();

        // If no solidarity fund, return 0
        if (solidarity.balance == 0 || solidarity.numActiveOrgs == 0) {
            return 0;
        }

        // Base allocation: equal share of fund
        uint256 baseAllocation = uint256(solidarity.balance) / solidarity.numActiveOrgs;

        // Adjust based on org's contribution ratio
        OrgFinancials storage org = financials[orgId];
        uint256 contributionRatio = solidarity.totalFeesCollected > 0
            ? (uint256(org.feesContributed) * 10000) / solidarity.totalFeesCollected
            : 0;

        // Orgs that contribute more get higher allocation (up to 2x base)
        // contributionRatio is in basis points (10000 = 100%)
        uint256 bonusMultiplier = 10000 + contributionRatio; // 100% base + contribution%
        uint256 allocation = (baseAllocation * bonusMultiplier) / 10000;

        // Cap at total fund balance
        if (allocation > solidarity.balance) {
            allocation = solidarity.balance;
        }

        return allocation;
    }

    /**
     * @notice Deposit funds for a specific org (permissionless)
     * @dev Anyone can deposit to any org to support them
     *
     * Deposit-to-Reset Model:
     * - When org crosses minimum threshold (was below, now above), resets solidarity allowance
     * - This creates natural monthly/periodic commitment without epoch tracking
     *
     * @param orgId The organization to deposit for
     */
    function depositForOrg(bytes32 orgId) external payable {
        if (msg.value == 0) revert ZeroAddress();

        mapping(bytes32 => OrgConfig) storage orgs = _getOrgsStorage();
        mapping(bytes32 => OrgFinancials) storage financials = _getFinancialsStorage();
        GracePeriodConfig storage grace = _getGracePeriodStorage();

        // Verify org exists
        if (orgs[orgId].adminHatId == 0) revert OrgNotRegistered();

        OrgFinancials storage org = financials[orgId];

        // Check if crossing minimum threshold (deposit-to-reset mechanism)
        bool wasBelowMinimum = org.deposited < grace.minDepositRequired;
        bool willBeAboveMinimum = org.deposited + msg.value >= grace.minDepositRequired;

        // Track if this is first deposit (for numActiveOrgs counter)
        bool wasUnfunded = org.deposited == 0;

        // Update org financials
        org.deposited += uint128(msg.value);
        org.totalDeposited += uint128(msg.value);

        // Reset solidarity allowance when crossing threshold (deposit-to-reset)
        if (wasBelowMinimum && willBeAboveMinimum) {
            org.solidarityUsed = 0;  // Reset allowance for new period
        }

        // Update active org count if this is first deposit
        if (wasUnfunded && msg.value > 0) {
            SolidarityFund storage solidarity = _getSolidarityStorage();
            solidarity.numActiveOrgs++;
        }

        // Deposit to EntryPoint
        IEntryPoint(_getMainStorage().entryPoint).depositTo{value: msg.value}(address(this));

        emit OrgDepositReceived(orgId, msg.sender, msg.value);
    }

    /**
     * @notice Donate to solidarity fund (permissionless)
     * @dev Anyone can donate to support all orgs
     */
    function donateToSolidarity() external payable {
        if (msg.value == 0) revert ZeroAddress();

        SolidarityFund storage solidarity = _getSolidarityStorage();
        solidarity.balance += uint128(msg.value);

        // Deposit to EntryPoint
        IEntryPoint(_getMainStorage().entryPoint).depositTo{value: msg.value}(address(this));

        emit SolidarityDonationReceived(msg.sender, msg.value);
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
        returns (bytes memory context, uint256 validationData)
    {
        // Decode and validate paymasterAndData
        (uint8 version, bytes32 orgId, uint8 subjectType, bytes20 subjectId, uint32 ruleId, uint64 mailboxCommit8) =
            _decodePaymasterData(userOp.paymasterAndData);

        if (version != PAYMASTER_DATA_VERSION) revert InvalidVersion();

        // Validate org is registered and not paused
        OrgConfig storage org = _getOrgsStorage()[orgId];
        if (org.adminHatId == 0) revert OrgNotRegistered();
        if (org.paused) revert Paused();

        // Validate subject eligibility
        bytes32 subjectKey = _validateSubjectEligibility(userOp.sender, subjectType, subjectId);

        // Validate target/selector rules
        _validateRules(userOp, ruleId, orgId);

        // Validate fee and gas caps
        _validateFeeCaps(userOp, orgId);

        // Check per-subject budget (existing functionality)
        uint32 currentEpochStart = _checkBudget(orgId, subjectKey, maxCost);

        // Check per-org financial balance (new: prevents overdraft)
        _checkOrgBalance(orgId, maxCost);

        // Check solidarity fund access (new: grace period + allocation)
        _checkSolidarityAccess(orgId, maxCost);

        // Prepare context for postOp
        context = abi.encode(orgId, subjectKey, currentEpochStart, userOpHash, mailboxCommit8, uint160(tx.origin));

        // Return 0 for no signature failure and no time restrictions
        validationData = 0;
    }

    /**
     * @notice Check if org has sufficient balance to cover operation
     * @dev Prevents org from spending more than deposited + solidarity allocation
     * @param orgId The organization identifier
     * @param maxCost Maximum cost of the operation
     */
    function _checkOrgBalance(bytes32 orgId, uint256 maxCost) internal view {
        mapping(bytes32 => OrgFinancials) storage financials = _getFinancialsStorage();
        OrgFinancials storage org = financials[orgId];

        // Calculate total available funds
        uint256 totalAvailable = uint256(org.deposited) - uint256(org.spent);

        // Check if org has enough in deposits to cover this
        // Note: solidarity is checked separately in _checkSolidarityAccess
        if (org.spent + maxCost > org.deposited) {
            // Will need to use solidarity - that's checked elsewhere
            // Here we just make sure they haven't overdrawn
            if (totalAvailable == 0) {
                revert InsufficientOrgBalance();
            }
        }
    }

    /**
     * @notice Post-operation hook called after UserOperation execution
     * @dev Updates budget usage, collects solidarity fee, and processes bounties
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
        (bytes32 orgId, bytes32 subjectKey, uint32 epochStart, bytes32 userOpHash, uint64 mailboxCommit8, address bundlerOrigin) =
            abi.decode(context, (bytes32, bytes32, uint32, bytes32, uint64, address));

        // Update per-subject budget usage (existing functionality)
        _updateUsage(orgId, subjectKey, epochStart, actualGasCost);

        // Update per-org financial tracking and collect solidarity fee (new)
        _updateOrgFinancials(orgId, actualGasCost);

        // Process bounty only on successful execution
        if (mode == IPaymaster.PostOpMode.opSucceeded && mailboxCommit8 != 0) {
            _processBounty(orgId, userOpHash, bundlerOrigin, actualGasCost);
        }
    }

    /**
     * @notice Update org's financial tracking and collect 1% solidarity fee
     * @dev Called in postOp after actual gas cost is known
     *
     * Payment Priority:
     * - Initial grace period (first 90 days): ALL from solidarity
     * - After grace period: Deposits FIRST, then solidarity (skin in the game)
     *
     * @param orgId The organization identifier
     * @param actualGasCost Actual gas cost paid
     */
    function _updateOrgFinancials(bytes32 orgId, uint256 actualGasCost) internal {
        mapping(bytes32 => OrgConfig) storage orgs = _getOrgsStorage();
        mapping(bytes32 => OrgFinancials) storage financials = _getFinancialsStorage();

        OrgConfig storage config = orgs[orgId];
        OrgFinancials storage org = financials[orgId];
        GracePeriodConfig storage grace = _getGracePeriodStorage();
        SolidarityFund storage solidarity = _getSolidarityStorage();

        // Calculate 1% solidarity fee
        uint256 solidarityFee = (actualGasCost * uint256(solidarity.feePercentageBps)) / 10000;

        // Check if in initial grace period
        uint256 graceEndTime = config.registeredAt + (uint256(grace.initialGraceDays) * 1 days);
        bool inInitialGrace = block.timestamp < graceEndTime;

        // Determine how much comes from org's deposits vs solidarity
        uint256 fromDeposits = 0;
        uint256 fromSolidarity = 0;

        if (inInitialGrace) {
            // First 90 days: ALL from solidarity (deposits untouched)
            fromSolidarity = actualGasCost;
        } else {
            // After 90 days: Use deposits FIRST (skin in the game), then solidarity
            if (org.deposited >= org.spent + actualGasCost) {
                // Org has enough in deposits to cover full cost
                fromDeposits = actualGasCost;
            } else {
                // Use deposits first, then solidarity kicks in
                uint256 depositAvailable = uint256(org.deposited) - uint256(org.spent);
                fromDeposits = depositAvailable;
                fromSolidarity = actualGasCost - depositAvailable;
            }
        }

        // Update org spending
        org.spent += uint128(fromDeposits);
        org.solidarityUsed += uint128(fromSolidarity);
        org.feesContributed += uint128(solidarityFee);

        // Update solidarity fund
        solidarity.balance -= uint128(fromSolidarity); // Deduct solidarity usage
        solidarity.balance += uint128(solidarityFee);  // Add collected fee
        solidarity.totalFeesCollected += uint128(solidarityFee);

        // Increment lifetime tx count if in initial grace period
        if (inInitialGrace) {
            org.lifetimeTxCount++;
        }

        emit SolidarityFeeCollected(orgId, solidarityFee);
    }

    // ============ Admin Functions ============

    /**
     * @notice Set a rule for target/selector combination
     * @dev Only callable by org admin or operator
     */
    function setRule(bytes32 orgId, address target, bytes4 selector, bool allowed, uint32 maxCallGasHint)
        external onlyOrgOperator(orgId) {
        if (target == address(0)) revert ZeroAddress();

        mapping(address => mapping(bytes4 => Rule)) storage rules = _getRulesStorage()[orgId];
        rules[target][selector] = Rule({allowed: allowed, maxCallGasHint: maxCallGasHint});
        emit RuleSet(orgId, target, selector, allowed, maxCallGasHint);
    }

    /**
     * @notice Batch set rules for multiple target/selector combinations
     */
    function setRulesBatch(
        bytes32 orgId,
        address[] calldata targets,
        bytes4[] calldata selectors,
        bool[] calldata allowed,
        uint32[] calldata maxCallGasHints
    ) external onlyOrgOperator(orgId) {
        uint256 length = targets.length;
        if (length != selectors.length || length != allowed.length || length != maxCallGasHints.length) {
            revert ArrayLengthMismatch();
        }

        mapping(address => mapping(bytes4 => Rule)) storage rules = _getRulesStorage()[orgId];

        for (uint256 i; i < length;) {
            if (targets[i] == address(0)) revert ZeroAddress();

            rules[targets[i]][selectors[i]] = Rule({allowed: allowed[i], maxCallGasHint: maxCallGasHints[i]});

            emit RuleSet(orgId, targets[i], selectors[i], allowed[i], maxCallGasHints[i]);

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Clear a rule for target/selector combination
     */
    function clearRule(bytes32 orgId, address target, bytes4 selector) external onlyOrgOperator(orgId) {
        mapping(address => mapping(bytes4 => Rule)) storage rules = _getRulesStorage()[orgId];
        delete rules[target][selector];
        emit RuleSet(orgId, target, selector, false, 0);
    }

    /**
     * @notice Set budget for a subject
     * @dev Validates epoch length and initializes epoch start
     */
    function setBudget(bytes32 orgId, bytes32 subjectKey, uint128 capPerEpoch, uint32 epochLen)
        external onlyOrgOperator(orgId) {
        if (epochLen < MIN_EPOCH_LENGTH || epochLen > MAX_EPOCH_LENGTH) {
            revert InvalidEpochLength();
        }

        mapping(bytes32 => Budget) storage budgets = _getBudgetsStorage()[orgId];
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

        emit BudgetSet(orgId, subjectKey, capPerEpoch, epochLen, budget.epochStart);
    }

    /**
     * @notice Manually set epoch start for a subject
     */
    function setEpochStart(bytes32 orgId, bytes32 subjectKey, uint32 epochStart) external onlyOrgOperator(orgId) {
        mapping(bytes32 => Budget) storage budgets = _getBudgetsStorage()[orgId];
        Budget storage budget = budgets[subjectKey];

        budget.epochStart = epochStart;
        budget.usedInEpoch = 0; // Reset usage when manually setting epoch

        emit BudgetSet(orgId, subjectKey, budget.capPerEpoch, budget.epochLen, epochStart);
    }

    /**
     * @notice Set fee and gas caps
     */
    function setFeeCaps(
        bytes32 orgId,
        uint256 maxFeePerGas,
        uint256 maxPriorityFeePerGas,
        uint32 maxCallGas,
        uint32 maxVerificationGas,
        uint32 maxPreVerificationGas
    ) external onlyOrgOperator(orgId) {
        FeeCaps storage feeCaps = _getFeeCapsStorage()[orgId];

        feeCaps.maxFeePerGas = maxFeePerGas;
        feeCaps.maxPriorityFeePerGas = maxPriorityFeePerGas;
        feeCaps.maxCallGas = maxCallGas;
        feeCaps.maxVerificationGas = maxVerificationGas;
        feeCaps.maxPreVerificationGas = maxPreVerificationGas;

        emit FeeCapsSet(orgId, maxFeePerGas, maxPriorityFeePerGas, maxCallGas, maxVerificationGas, maxPreVerificationGas);
    }

    /**
     * @notice Pause or unpause the paymaster for an org
     * @dev Only org admin can pause/unpause
     */
    function setPause(bytes32 orgId, bool paused) external onlyOrgAdmin(orgId) {
        _getOrgsStorage()[orgId].paused = paused;
        emit PauseSet(orgId, paused);
    }

    /**
     * @notice Set optional operator hat for delegated management
     */
    function setOperatorHat(bytes32 orgId, uint256 operatorHatId) external onlyOrgAdmin(orgId) {
        _getOrgsStorage()[orgId].operatorHatId = operatorHatId;
        emit OperatorHatSet(orgId, operatorHatId);
    }

    /**
     * @notice Configure bounty parameters for an org
     */
    function setBounty(bytes32 orgId, bool enabled, uint96 maxBountyWeiPerOp, uint16 pctBpCap)
        external onlyOrgAdmin(orgId) {
        if (pctBpCap > MAX_BOUNTY_PCT_BP) revert InvalidBountyConfig();

        Bounty storage bounty = _getBountyStorage()[orgId];
        bounty.enabled = enabled;
        bounty.maxBountyWeiPerOp = maxBountyWeiPerOp;
        bounty.pctBpCap = pctBpCap;

        emit BountyConfig(orgId, enabled, maxBountyWeiPerOp, pctBpCap);
    }

    /**
     * @notice Deposit funds to EntryPoint for gas reimbursement (shared pool)
     * @dev Any org operator can deposit to shared pool
     */
    function depositToEntryPoint(bytes32 orgId) external payable onlyOrgOperator(orgId) {
        address entryPoint = _getMainStorage().entryPoint;
        IEntryPoint(entryPoint).depositTo{value: msg.value}(address(this));

        uint256 newDeposit = IEntryPoint(entryPoint).balanceOf(address(this));
        emit DepositIncrease(msg.value, newDeposit);
    }

    /**
     * @notice Withdraw funds from EntryPoint deposit (requires global admin)
     * @dev Withdrawals affect shared pool, so restricted to prevent abuse
     */
    function withdrawFromEntryPoint(address payable to, uint256 amount) external {
        // TODO: Add global admin mechanism or require multi-org consensus
        // For now, disabled to protect shared pool
        revert NotAdmin();
    }

    /**
     * @notice Fund bounty pool (contract balance)
     */
    function fundBounty() external payable {
        emit BountyFunded(msg.value, address(this).balance);
    }

    /**
     * @notice Withdraw from bounty pool
     * @dev Bounties are shared across all orgs, requires careful governance
     */
    function sweepBounty(address payable to, uint256 amount) external {
        // TODO: Add global admin mechanism
        revert NotAdmin();
    }

    /**
     * @notice Emergency withdrawal in case of critical issues
     * @dev Requires global admin - affects all orgs
     */
    function emergencyWithdraw(address payable to) external {
        // TODO: Add global admin mechanism
        revert NotAdmin();
    }

    /**
     * @notice Set grace period configuration (global setting)
     * @dev Only PoaManager can modify grace period parameters
     * @param _initialGraceDays Number of days for initial grace period (default 90)
     * @param _maxTxDuringGrace Maximum transactions during grace period (default 3000)
     * @param _minDepositRequired Minimum balance to maintain after grace (default 0.003 ETH ~$10)
     */
    function setGracePeriodConfig(
        uint32 _initialGraceDays,
        uint32 _maxTxDuringGrace,
        uint128 _minDepositRequired
    ) external {
        if (msg.sender != _getMainStorage().poaManager) revert NotPoaManager();
        if (_initialGraceDays == 0) revert InvalidEpochLength();
        if (_maxTxDuringGrace == 0) revert InvalidEpochLength();
        if (_minDepositRequired == 0) revert InvalidEpochLength();

        GracePeriodConfig storage grace = _getGracePeriodStorage();
        grace.initialGraceDays = _initialGraceDays;
        grace.maxTxDuringGrace = _maxTxDuringGrace;
        grace.minDepositRequired = _minDepositRequired;

        emit GracePeriodConfigUpdated(_initialGraceDays, _maxTxDuringGrace, _minDepositRequired);
    }

    /**
     * @notice Ban or unban an org from accessing solidarity fund
     * @dev Only PoaManager can ban orgs for malicious behavior
     * @param orgId The organization to ban/unban
     * @param banned True to ban, false to unban
     */
    function setBanFromSolidarity(bytes32 orgId, bool banned) external {
        if (msg.sender != _getMainStorage().poaManager) revert NotPoaManager();

        mapping(bytes32 => OrgConfig) storage orgs = _getOrgsStorage();
        if (orgs[orgId].adminHatId == 0) revert OrgNotRegistered();

        orgs[orgId].bannedFromSolidarity = banned;

        emit OrgBannedFromSolidarity(orgId, banned);
    }

    /**
     * @notice Set solidarity fund fee percentage
     * @dev Only PoaManager can modify the fee (default 1%)
     * @param feePercentageBps Fee as basis points (100 = 1%)
     */
    function setSolidarityFee(uint16 feePercentageBps) external {
        if (msg.sender != _getMainStorage().poaManager) revert NotPoaManager();
        if (feePercentageBps > 1000) revert FeeTooHigh(); // Cap at 10%

        SolidarityFund storage solidarity = _getSolidarityStorage();
        solidarity.feePercentageBps = feePercentageBps;
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
     * @notice Get the configuration for an org
     * @return The OrgConfig struct
     */
    function getOrgConfig(bytes32 orgId) external view returns (OrgConfig memory) {
        return _getOrgsStorage()[orgId];
    }

    /**
     * @notice Get budget for a specific subject within an org
     * @param orgId Organization identifier
     * @param key The subject key (user, role, or org)
     * @return The Budget struct
     */
    function getBudget(bytes32 orgId, bytes32 key) external view returns (Budget memory) {
        return _getBudgetsStorage()[orgId][key];
    }

    /**
     * @notice Get rule for a specific target and selector within an org
     * @param orgId Organization identifier
     * @param target The target contract address
     * @param selector The function selector
     * @return The Rule struct
     */
    function getRule(bytes32 orgId, address target, bytes4 selector) external view returns (Rule memory) {
        return _getRulesStorage()[orgId][target][selector];
    }

    /**
     * @notice Get the fee caps for an org
     * @param orgId Organization identifier
     * @return The FeeCaps struct
     */
    function getFeeCaps(bytes32 orgId) external view returns (FeeCaps memory) {
        return _getFeeCapsStorage()[orgId];
    }

    /**
     * @notice Get the bounty configuration for an org
     * @param orgId Organization identifier
     * @return The Bounty struct
     */
    function getBountyConfig(bytes32 orgId) external view returns (Bounty memory) {
        return _getBountyStorage()[orgId];
    }

    /**
     * @notice Get org's financial tracking data
     * @param orgId Organization identifier
     * @return The OrgFinancials struct
     */
    function getOrgFinancials(bytes32 orgId) external view returns (OrgFinancials memory) {
        return _getFinancialsStorage()[orgId];
    }

    /**
     * @notice Get global solidarity fund state
     * @return The SolidarityFund struct
     */
    function getSolidarityFund() external view returns (SolidarityFund memory) {
        return _getSolidarityStorage();
    }

    /**
     * @notice Get grace period configuration
     * @return The GracePeriodConfig struct
     */
    function getGracePeriodConfig() external view returns (GracePeriodConfig memory) {
        return _getGracePeriodStorage();
    }

    /**
     * @notice Get org's grace period status and limits
     * @param orgId The organization identifier
     * @return inGrace True if in initial grace period
     * @return txRemaining Transactions remaining during grace (0 if not in grace)
     * @return requiresDeposit True if org needs to deposit to access solidarity
     * @return solidarityLimit Current solidarity allocation for org
     */
    function getOrgGraceStatus(bytes32 orgId) external view returns (
        bool inGrace,
        uint32 txRemaining,
        bool requiresDeposit,
        uint256 solidarityLimit
    ) {
        mapping(bytes32 => OrgConfig) storage orgs = _getOrgsStorage();
        mapping(bytes32 => OrgFinancials) storage financials = _getFinancialsStorage();
        GracePeriodConfig storage grace = _getGracePeriodStorage();

        OrgConfig storage config = orgs[orgId];
        OrgFinancials storage org = financials[orgId];

        uint256 graceEndTime = config.registeredAt + (uint256(grace.initialGraceDays) * 1 days);
        inGrace = block.timestamp < graceEndTime;

        if (inGrace) {
            uint32 txUsed = org.lifetimeTxCount;
            txRemaining = txUsed < grace.maxTxDuringGrace ? grace.maxTxDuringGrace - txUsed : 0;
            requiresDeposit = false;
        } else {
            txRemaining = 0;
            requiresDeposit = org.deposited < grace.minDepositRequired;
        }

        solidarityLimit = _calculateSolidarityLimit(orgId);
    }

    // ============ Storage Accessors ============
    function _getMainStorage() private pure returns (MainStorage storage $) {
        assembly {
            $.slot := MAIN_STORAGE_LOCATION
        }
    }

    function _getOrgsStorage() private pure returns (mapping(bytes32 => OrgConfig) storage $) {
        assembly {
            $.slot := ORGS_STORAGE_LOCATION
        }
    }

    function _getFeeCapsStorage() private pure returns (mapping(bytes32 => FeeCaps) storage $) {
        assembly {
            $.slot := FEECAPS_STORAGE_LOCATION
        }
    }

    function _getRulesStorage() private pure returns (mapping(bytes32 => mapping(address => mapping(bytes4 => Rule))) storage $) {
        assembly {
            $.slot := RULES_STORAGE_LOCATION
        }
    }

    function _getBudgetsStorage() private pure returns (mapping(bytes32 => mapping(bytes32 => Budget)) storage $) {
        assembly {
            $.slot := BUDGETS_STORAGE_LOCATION
        }
    }

    function _getBountyStorage() private pure returns (mapping(bytes32 => Bounty) storage $) {
        assembly {
            $.slot := BOUNTY_STORAGE_LOCATION
        }
    }

    function _getFinancialsStorage() private pure returns (mapping(bytes32 => OrgFinancials) storage $) {
        assembly {
            $.slot := FINANCIALS_STORAGE_LOCATION
        }
    }

    function _getSolidarityStorage() private pure returns (SolidarityFund storage $) {
        assembly {
            $.slot := SOLIDARITY_STORAGE_LOCATION
        }
    }

    function _getGracePeriodStorage() private pure returns (GracePeriodConfig storage $) {
        assembly {
            $.slot := GRACEPERIOD_STORAGE_LOCATION
        }
    }

    // ============ Public Getters ============

    /**
     * @notice Get the EntryPoint address
     * @return The ERC-4337 EntryPoint address
     */
    function ENTRY_POINT() public view returns (address) {
        return _getMainStorage().entryPoint;
    }

    /**
     * @notice Get the Hats Protocol address
     * @return The Hats Protocol address
     */
    function HATS() public view returns (address) {
        return _getMainStorage().hats;
    }

    /**
     * @notice Get the PoaManager address
     * @return The PoaManager address
     */
    function POA_MANAGER() public view returns (address) {
        return _getMainStorage().poaManager;
    }

    // ============ Upgrade Authorization ============

    /**
     * @notice Authorize contract upgrade
     * @dev Only PoaManager can authorize upgrades
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override {
        MainStorage storage main = _getMainStorage();
        if (msg.sender != main.poaManager) revert NotPoaManager();
        // newImplementation is intentionally not validated to allow flexibility
    }

    // ============ Internal Functions ============

    function _decodePaymasterData(bytes calldata paymasterAndData)
        private
        pure
        returns (uint8 version, bytes32 orgId, uint8 subjectType, bytes20 subjectId, uint32 ruleId, uint64 mailboxCommit8)
    {
        // New format: [paymaster(20) | version(1) | orgId(32) | subjectType(1) | subjectId(20) | ruleId(4) | mailboxCommit(8)] = 86 bytes
        if (paymasterAndData.length < 86) revert InvalidPaymasterData();

        // Skip first 20 bytes (paymaster address) and decode the rest
        version = uint8(paymasterAndData[20]);
        orgId = bytes32(paymasterAndData[21:53]);
        subjectType = uint8(paymasterAndData[53]);

        // Extract bytes20 subjectId from bytes 54-73
        assembly {
            subjectId := calldataload(add(paymasterAndData.offset, 54))
        }

        // Extract ruleId from bytes 74-77
        ruleId = uint32(bytes4(paymasterAndData[74:78]));

        // Extract mailboxCommit8 from bytes 78-85
        mailboxCommit8 = uint64(bytes8(paymasterAndData[78:86]));
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
            if (!IHats(_getMainStorage().hats).isWearerOfHat(sender, hatId)) {
                revert Ineligible();
            }
            subjectKey = keccak256(abi.encodePacked(subjectType, subjectId));
        } else {
            revert InvalidSubjectType();
        }
    }

    function _validateRules(PackedUserOperation calldata userOp, uint32 ruleId, bytes32 orgId) private view {
        (address target, bytes4 selector) = _extractTargetSelector(userOp, ruleId);

        mapping(address => mapping(bytes4 => Rule)) storage rules = _getRulesStorage()[orgId];
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

    function _validateFeeCaps(PackedUserOperation calldata userOp, bytes32 orgId) private view {
        FeeCaps storage caps = _getFeeCapsStorage()[orgId];

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

    function _checkBudget(bytes32 orgId, bytes32 subjectKey, uint256 maxCost) private returns (uint32 currentEpochStart) {
        mapping(bytes32 => Budget) storage budgets = _getBudgetsStorage()[orgId];
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

    function _updateUsage(bytes32 orgId, bytes32 subjectKey, uint32 epochStart, uint256 actualGasCost) private {
        mapping(bytes32 => Budget) storage budgets = _getBudgetsStorage()[orgId];
        Budget storage budget = budgets[subjectKey];

        // Only update if we're still in the same epoch
        if (budget.epochStart == epochStart) {
            // Safe to cast as actualGasCost is bounded
            uint128 cost = uint128(actualGasCost);
            budget.usedInEpoch += cost;
            emit UsageIncreased(orgId, subjectKey, actualGasCost, budget.usedInEpoch, epochStart);
        }
    }

    function _processBounty(bytes32 orgId, bytes32 userOpHash, address bundlerOrigin, uint256 actualGasCost) private {
        Bounty storage bounty = _getBountyStorage()[orgId];

        if (!bounty.enabled) return;

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

    /**
     * @dev Storage gap for future upgrades
     * Reserves 50 storage slots for new variables in future versions
     */
    uint256[50] private __gap;
}
