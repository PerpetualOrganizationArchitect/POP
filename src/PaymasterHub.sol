// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPaymaster} from "./interfaces/IPaymaster.sol";
import {IEntryPoint} from "./interfaces/IEntryPoint.sol";
import {PackedUserOperation, UserOpLib} from "./interfaces/PackedUserOperation.sol";
import {IHats} from "lib/hats-protocol/src/Interfaces/IHats.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {
    ReentrancyGuardUpgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IERC165} from "lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";
import {ECDSA} from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";

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
    error GracePeriodSpendLimitReached();
    error InsufficientDepositForSolidarity();
    error SolidarityLimitExceeded();
    error InsufficientOrgBalance();
    error OrgIsBanned();
    error InsufficientFunds();
    error VouchExpired();
    error VouchAlreadyUsed();
    error InvalidVouchSignature();
    error VoucherNotAuthorized();
    error VoucherHatNotSet();
    error OnboardingDisabled();
    error OnboardingDailyLimitExceeded();

    // ============ Constants ============
    uint8 private constant PAYMASTER_DATA_VERSION = 1;
    uint8 private constant SUBJECT_TYPE_ACCOUNT = 0x00;
    uint8 private constant SUBJECT_TYPE_HAT = 0x01;
    uint8 private constant SUBJECT_TYPE_VOUCHED = 0x02;
    uint8 private constant SUBJECT_TYPE_POA_ONBOARDING = 0x03;

    uint32 private constant RULE_ID_GENERIC = 0x00000000;
    uint32 private constant RULE_ID_EXECUTOR = 0x00000001;
    uint32 private constant RULE_ID_COARSE = 0x000000FF;

    uint32 private constant MIN_EPOCH_LENGTH = 1 hours;
    uint32 private constant MAX_EPOCH_LENGTH = 365 days;
    uint256 private constant MAX_BOUNTY_PCT_BP = 10000; // 100%

    /// @notice Minimum paymasterAndData length for vouched subject type
    /// @dev Format: base(86) + expiry(6) + signature(65) = 157 bytes minimum
    uint256 private constant VOUCH_DATA_MIN_LENGTH = 157;

    // ============ Events ============
    event PaymasterInitialized(address indexed entryPoint, address indexed hats, address indexed poaManager);
    event OrgRegistered(bytes32 indexed orgId, uint256 adminHatId, uint256 operatorHatId);
    event RuleSet(
        bytes32 indexed orgId, address indexed target, bytes4 indexed selector, bool allowed, uint32 maxCallGasHint
    );
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
    event UsageIncreased(
        bytes32 indexed orgId, bytes32 subjectKey, uint256 delta, uint128 usedInEpoch, uint32 epochStart
    );
    event UserOpPosted(bytes32 indexed opHash, address indexed postedBy);
    event EmergencyWithdraw(address indexed to, uint256 amount);
    event OrgDepositReceived(bytes32 indexed orgId, address indexed from, uint256 amount);
    event SolidarityFeeCollected(bytes32 indexed orgId, uint256 amount);
    event SolidarityDonationReceived(address indexed from, uint256 amount);
    event GracePeriodConfigUpdated(uint32 initialGraceDays, uint128 maxSpendDuringGrace, uint128 minDepositRequired);
    event OrgBannedFromSolidarity(bytes32 indexed orgId, bool banned);
    event VoucherHatSet(bytes32 indexed orgId, uint256 voucherHatId);
    event VouchUsed(bytes32 indexed orgId, address indexed account, address indexed voucher);
    event OnboardingConfigUpdated(uint128 maxGasPerCreation, uint128 dailyCreationLimit, bool enabled);
    event OnboardingAccountCreated(address indexed account, uint256 gasCost);

    // ============ Storage Variables ============
    /// @custom:storage-location erc7201:poa.paymasterhub.main
    struct MainStorage {
        address entryPoint;
        address hats;
        address poaManager;
    }

    // keccak256(abi.encode(uint256(keccak256("poa.paymasterhub.main")) - 1))
    bytes32 private constant MAIN_STORAGE_LOCATION = 0x79313178bb7ec733585695efb4bda9fb0a2460b07c17173a160d53a584d7fdf1;

    // ============ Storage Structs ============

    /**
     * @dev Organization configuration
     * Storage optimization: registeredAt packed with paused to save gas
     */
    struct OrgConfig {
        uint256 adminHatId; // Slot 0
        uint256 operatorHatId; // Slot 1: Optional role for budget/rule management
        uint256 voucherHatId; // Slot 2: Hat ID for members who can vouch for new users
        bool paused; // Slot 3 (1 byte)
        uint40 registeredAt; // Slot 3 (5 bytes): UNIX timestamp, good until year 36812
        bool bannedFromSolidarity; // Slot 3 (1 byte)
        // 25 bytes remaining in slot 3 for future use
    }

    /**
     * @dev Per-org financial tracking for solidarity fund accounting
     */
    struct OrgFinancials {
        uint128 deposited; // Current balance deposited by org
        uint128 totalDeposited; // Cumulative lifetime deposits (never decreases)
        uint128 spent; // Total spent from org's own deposits
        uint128 solidarityUsedThisPeriod; // Solidarity used in current 90-day period
        uint32 periodStart; // Timestamp when current 90-day period started
        uint224 reserved; // Padding for future use
    }

    /**
     * @dev Global solidarity fund state
     */
    struct SolidarityFund {
        uint128 balance; // Current solidarity fund balance
        uint32 numActiveOrgs; // Number of orgs with deposits > 0
        uint16 feePercentageBps; // Fee as basis points (100 = 1%)
        uint208 reserved; // Padding
    }

    /**
     * @dev Grace period configuration for unfunded orgs
     */
    struct GracePeriodConfig {
        uint32 initialGraceDays; // Startup period with zero deposits (default 90)
        uint128 maxSpendDuringGrace; // Max spending during grace period (default 0.01 ETH ~$30)
        uint128 minDepositRequired; // Minimum balance to maintain after grace (default 0.003 ETH ~$10)
    }

    /**
     * @dev POA onboarding configuration for account creation from solidarity fund
     */
    struct OnboardingConfig {
        uint128 maxGasPerCreation; // Max gas per account creation (~200k)
        uint128 dailyCreationLimit; // Max accounts globally per day
        uint128 createdToday; // Counter for current day
        uint32 currentDay; // Day tracker (timestamp / 1 days)
        bool enabled; // Whether onboarding sponsorship is active
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
    bytes32 private constant ORGS_STORAGE_LOCATION = 0x1577b5f3d975f3e4c3ad36823cfc47ce59d96a4692a043664a68f0cf2b1a08e5;

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
        0xc5d8b6edce490eeae75e971366b4e3a6142abb5df4486ab4290826e6cd008210;

    // keccak256(abi.encode(uint256(keccak256("poa.paymasterhub.solidarity")) - 1))
    bytes32 private constant SOLIDARITY_STORAGE_LOCATION =
        0xa83be0d588222d6e3c8e88a987c1439474749e44cafa67ced60ef5911863ad5b;

    // keccak256(abi.encode(uint256(keccak256("poa.paymasterhub.graceperiod")) - 1))
    bytes32 private constant GRACEPERIOD_STORAGE_LOCATION =
        0xb32fa2cc2be738bb7360ed872bdb5f34f0611b5e6c897349c7f50d1becdb3984;

    // keccak256("poa.paymasterhub.usedvouches")
    bytes32 private constant USEDVOUCHES_STORAGE_LOCATION =
        0x86e9dc53a59330278f5c7228b9372eecbe7ed09b3412489de7fe1e046b46bbaa;

    // keccak256("poa.paymasterhub.onboarding")
    bytes32 private constant ONBOARDING_STORAGE_LOCATION =
        0x4b1e497b56331764ad6bf7b8c88df82cd3770c256224ec222ba11219a197de90;

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

        // Initialize grace period with defaults (90 days, 0.01 ETH ~$30 spend, 0.003 ETH ~$10 deposit)
        GracePeriodConfig storage grace = _getGracePeriodStorage();
        grace.initialGraceDays = 90;
        grace.maxSpendDuringGrace = 0.01 ether; // ~$30 worth of gas (~3000 tx on cheap L2s)
        grace.minDepositRequired = 0.003 ether; // ~$10 minimum deposit

        // Initialize onboarding config (enabled, ~200k gas per creation, 1000 accounts/day)
        OnboardingConfig storage onboarding = _getOnboardingStorage();
        onboarding.maxGasPerCreation = 200000; // ~200k gas for account creation
        onboarding.dailyCreationLimit = 1000; // 1000 accounts per day
        onboarding.enabled = true;

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
        registerOrgWithVoucher(orgId, adminHatId, operatorHatId, 0);
    }

    /**
     * @notice Register a new organization with voucher hat support
     * @dev Called by OrgDeployer during org creation
     * @param orgId Unique organization identifier
     * @param adminHatId Hat ID for org admin (topHat)
     * @param operatorHatId Optional hat ID for operators (0 if none)
     * @param voucherHatId Hat ID for members who can vouch for new users (0 if disabled)
     */
    function registerOrgWithVoucher(bytes32 orgId, uint256 adminHatId, uint256 operatorHatId, uint256 voucherHatId)
        public
    {
        if (adminHatId == 0) revert ZeroAddress();

        mapping(bytes32 => OrgConfig) storage orgs = _getOrgsStorage();
        if (orgs[orgId].adminHatId != 0) revert OrgAlreadyRegistered();

        orgs[orgId] = OrgConfig({
            adminHatId: adminHatId,
            operatorHatId: operatorHatId,
            voucherHatId: voucherHatId,
            paused: false,
            registeredAt: uint40(block.timestamp),
            bannedFromSolidarity: false
        });

        emit OrgRegistered(orgId, adminHatId, operatorHatId);
        if (voucherHatId != 0) {
            emit VoucherHatSet(orgId, voucherHatId);
        }
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
            // Enforce spending limit only (configured to represent ~3000 tx worth of value)
            if (org.solidarityUsedThisPeriod + maxCost > grace.maxSpendDuringGrace) {
                revert GracePeriodSpendLimitReached();
            }
        } else {
            // After startup: must MAINTAIN minimum deposit (like $10/month commitment)
            // This checks deposited (current balance), not totalDeposited (cumulative)
            // Orgs must keep funds in reserve to access solidarity
            if (org.deposited < grace.minDepositRequired) {
                revert InsufficientDepositForSolidarity();
            }

            // Check against tier-based allowance (calculated in payment logic)
            // Tier 1: deposit 0.003 ETH → 0.006 ETH match → 0.009 ETH total per 90 days
            // Tier 2: deposit 0.006 ETH → 0.009 ETH match → 0.015 ETH total per 90 days
            // Tier 3: deposit >= 0.017 ETH → no match, self-funded
            uint256 matchAllowance = _calculateMatchAllowance(org.deposited, grace.minDepositRequired);
            if (org.solidarityUsedThisPeriod + maxCost > matchAllowance) {
                revert SolidarityLimitExceeded();
            }
        }
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

        // Check if period should reset (dual trigger)
        bool shouldResetPeriod = false;

        // Trigger 1: Time-based (90 days elapsed)
        if (org.periodStart > 0 && block.timestamp >= org.periodStart + 90 days) {
            shouldResetPeriod = true;
        }

        // Trigger 2: Crossing minimum threshold
        bool wasBelowMinimum = org.deposited < grace.minDepositRequired;
        bool willBeAboveMinimum = org.deposited + msg.value >= grace.minDepositRequired;
        if (wasBelowMinimum && willBeAboveMinimum) {
            shouldResetPeriod = true;
        }

        // Track if this is first deposit (for numActiveOrgs counter and period init)
        bool wasUnfunded = org.deposited == 0;

        // Update org financials
        org.deposited += uint128(msg.value);
        org.totalDeposited += uint128(msg.value);

        // Reset period when triggered
        if (shouldResetPeriod) {
            org.solidarityUsedThisPeriod = 0;
            org.periodStart = uint32(block.timestamp);
        } else if (wasUnfunded) {
            // Initialize period start on first deposit
            org.periodStart = uint32(block.timestamp);
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

        bytes32 subjectKey;
        uint32 currentEpochStart;

        // Handle POA onboarding separately (no org required)
        if (subjectType == SUBJECT_TYPE_POA_ONBOARDING) {
            // Validate POA onboarding eligibility
            subjectKey = _validateOnboardingEligibility(userOp.sender, maxCost);
            currentEpochStart = uint32(block.timestamp);

            // For onboarding, we don't validate org rules/caps/budgets
            // The onboarding config has its own limits
        } else {
            // Validate org is registered and not paused
            OrgConfig storage org = _getOrgsStorage()[orgId];
            if (org.adminHatId == 0) revert OrgNotRegistered();
            if (org.paused) revert Paused();

            // Validate subject eligibility
            if (subjectType == SUBJECT_TYPE_VOUCHED) {
                // Vouched onboarding: validate vouch signature from hat wearer
                subjectKey = _validateVouchedEligibility(userOp.sender, orgId, org, subjectId, userOp.paymasterAndData);
            } else {
                subjectKey = _validateSubjectEligibility(userOp.sender, subjectType, subjectId);
            }

            // Validate target/selector rules
            _validateRules(userOp, ruleId, orgId);

            // Validate fee and gas caps
            _validateFeeCaps(userOp, orgId);

            // Check per-subject budget (existing functionality)
            currentEpochStart = _checkBudget(orgId, subjectKey, maxCost);

            // Check per-org financial balance (new: prevents overdraft)
            _checkOrgBalance(orgId, maxCost);

            // Check solidarity fund access (new: grace period + allocation)
            _checkSolidarityAccess(orgId, maxCost);
        }

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
        (
            bytes32 orgId,
            bytes32 subjectKey,
            uint32 epochStart,
            bytes32 userOpHash,
            uint64 mailboxCommit8,
            address bundlerOrigin
        ) = abi.decode(context, (bytes32, bytes32, uint32, bytes32, uint64, address));

        // Check if this is POA onboarding (orgId will be bytes32(0))
        if (orgId == bytes32(0)) {
            // POA onboarding: deduct from solidarity fund, update counter
            _updateOnboardingUsage(subjectKey, actualGasCost);
        } else {
            // Regular org operation
            // Update per-subject budget usage (existing functionality)
            _updateUsage(orgId, subjectKey, epochStart, actualGasCost);

            // Update per-org financial tracking and collect solidarity fee (new)
            _updateOrgFinancials(orgId, actualGasCost);

            // Process bounty only on successful execution
            if (mode == IPaymaster.PostOpMode.opSucceeded && mailboxCommit8 != 0) {
                _processBounty(orgId, userOpHash, bundlerOrigin, actualGasCost);
            }
        }
    }

    /**
     * @notice Calculate solidarity match allowance based on deposit tier
     * @dev Progressive tier system with declining marginal match rates
     *
     * Tier 1: deposit = 1x min → match = 2x → total budget = 3x (e.g. 0.003 ETH → 0.009 ETH)
     * Tier 2: deposit = 2x min → match = 3x → total budget = 5x (e.g. 0.006 ETH → 0.015 ETH)
     * Tier 3: deposit >= 5x min → no match, self-funded
     *
     * @param deposited Current deposit balance
     * @param minDeposit Minimum deposit requirement (from grace config)
     * @return matchAllowance How much solidarity can be used per 90-day period
     */
    function _calculateMatchAllowance(uint256 deposited, uint256 minDeposit) internal pure returns (uint256) {
        // Below minimum = no match
        if (deposited < minDeposit) {
            return 0;
        }

        // Tier 1: 1x deposit → 2x match
        // E.g., 0.003 ETH deposit → 0.006 ETH match → 0.009 ETH total
        if (deposited <= minDeposit) {
            return deposited * 2;
        }

        // Tier 2: First 1x at 2x, second 1x at 1x
        // E.g., 0.006 ETH deposit → 0.006 (first) + 0.003 (second) = 0.009 ETH match → 0.015 ETH total
        if (deposited <= minDeposit * 2) {
            uint256 firstTierMatch = minDeposit * 2;
            uint256 secondTierMatch = deposited - minDeposit;
            return firstTierMatch + secondTierMatch;
        }

        // Tier 3: Self-sufficient, no match
        // Organizations with >= 5x minimum deposit don't need solidarity support
        return 0;
    }

    /**
     * @notice Update org's financial tracking and collect 1% solidarity fee
     * @dev Called in postOp after actual gas cost is known
     *
     * Payment Priority:
     * - Initial grace period (first 90 days): 100% from solidarity
     * - After grace period: 50/50 split between deposits and solidarity
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
            // Grace period: 100% from solidarity (deposits untouched)
            fromSolidarity = actualGasCost;
        } else {
            // Post-grace: 50/50 split with tier-based solidarity allowance
            // Calculate available balance (not cumulative deposits)
            uint256 depositAvailable = org.deposited > org.spent ? org.deposited - org.spent : 0;

            // Match allowance based on CURRENT BALANCE, not lifetime deposits
            uint256 matchAllowance = _calculateMatchAllowance(depositAvailable, grace.minDepositRequired);
            uint256 solidarityRemaining =
                matchAllowance > org.solidarityUsedThisPeriod ? matchAllowance - org.solidarityUsedThisPeriod : 0;

            uint256 halfCost = actualGasCost / 2;

            // Try 50/50 split
            fromDeposits = halfCost < depositAvailable ? halfCost : depositAvailable;
            fromSolidarity = halfCost < solidarityRemaining ? halfCost : solidarityRemaining;

            // If one pool is short, try to make up from the other
            uint256 covered = fromDeposits + fromSolidarity;
            if (covered < actualGasCost) {
                uint256 shortfall = actualGasCost - covered;

                // Try deposits first
                uint256 depositExtra = depositAvailable - fromDeposits;
                if (depositExtra > 0) {
                    uint256 additional = shortfall < depositExtra ? shortfall : depositExtra;
                    fromDeposits += additional;
                    shortfall -= additional;
                }

                // Then try solidarity
                if (shortfall > 0) {
                    uint256 solidarityExtra = solidarityRemaining - fromSolidarity;
                    if (solidarityExtra > 0) {
                        uint256 additional = shortfall < solidarityExtra ? shortfall : solidarityExtra;
                        fromSolidarity += additional;
                        shortfall -= additional;
                    }
                }

                // If still can't cover, revert
                if (shortfall > 0) {
                    revert InsufficientFunds();
                }
            }
        }

        // Update org spending
        org.spent += uint128(fromDeposits);
        org.solidarityUsedThisPeriod += uint128(fromSolidarity);

        // Update solidarity fund
        solidarity.balance -= uint128(fromSolidarity);
        solidarity.balance += uint128(solidarityFee);

        emit SolidarityFeeCollected(orgId, solidarityFee);
    }

    // ============ Admin Functions ============

    /**
     * @notice Set a rule for target/selector combination
     * @dev Only callable by org admin or operator
     */
    function setRule(bytes32 orgId, address target, bytes4 selector, bool allowed, uint32 maxCallGasHint)
        external
        onlyOrgOperator(orgId)
    {
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
        external
        onlyOrgOperator(orgId)
    {
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

        emit FeeCapsSet(
            orgId, maxFeePerGas, maxPriorityFeePerGas, maxCallGas, maxVerificationGas, maxPreVerificationGas
        );
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
     * @notice Set the voucher hat for an org
     * @dev Voucher hat wearers can sign vouches for new users to onboard gaslessly
     * @param orgId Organization identifier
     * @param voucherHatId Hat ID for vouchers (0 to disable vouching)
     */
    function setVoucherHat(bytes32 orgId, uint256 voucherHatId) external onlyOrgAdmin(orgId) {
        _getOrgsStorage()[orgId].voucherHatId = voucherHatId;
        emit VoucherHatSet(orgId, voucherHatId);
    }

    /**
     * @notice Configure bounty parameters for an org
     */
    function setBounty(bytes32 orgId, bool enabled, uint96 maxBountyWeiPerOp, uint16 pctBpCap)
        external
        onlyOrgAdmin(orgId)
    {
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
     * @param _maxSpendDuringGrace Maximum spending during grace period (default 0.01 ETH ~$30, represents ~3000 tx)
     * @param _minDepositRequired Minimum balance to maintain after grace (default 0.003 ETH ~$10)
     */
    function setGracePeriodConfig(uint32 _initialGraceDays, uint128 _maxSpendDuringGrace, uint128 _minDepositRequired)
        external
    {
        if (msg.sender != _getMainStorage().poaManager) revert NotPoaManager();
        if (_initialGraceDays == 0) revert InvalidEpochLength();
        if (_maxSpendDuringGrace == 0) revert InvalidEpochLength();
        if (_minDepositRequired == 0) revert InvalidEpochLength();

        GracePeriodConfig storage grace = _getGracePeriodStorage();
        grace.initialGraceDays = _initialGraceDays;
        grace.maxSpendDuringGrace = _maxSpendDuringGrace;
        grace.minDepositRequired = _minDepositRequired;

        emit GracePeriodConfigUpdated(_initialGraceDays, _maxSpendDuringGrace, _minDepositRequired);
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

    /**
     * @notice Configure POA onboarding for account creation from solidarity fund
     * @dev Only PoaManager can modify onboarding parameters
     * @param _maxGasPerCreation Maximum gas allowed per account creation (~200k)
     * @param _dailyCreationLimit Maximum accounts that can be created per day globally
     * @param _enabled Whether onboarding sponsorship is active
     */
    function setOnboardingConfig(uint128 _maxGasPerCreation, uint128 _dailyCreationLimit, bool _enabled) external {
        if (msg.sender != _getMainStorage().poaManager) revert NotPoaManager();

        OnboardingConfig storage onboarding = _getOnboardingStorage();
        onboarding.maxGasPerCreation = _maxGasPerCreation;
        onboarding.dailyCreationLimit = _dailyCreationLimit;
        onboarding.enabled = _enabled;

        emit OnboardingConfigUpdated(_maxGasPerCreation, _dailyCreationLimit, _enabled);
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
     * @notice Check if a vouch has been used for an account
     * @param orgId Organization identifier
     * @param account The account address that was vouched for
     * @return True if the vouch has been used
     */
    function isVouchUsed(bytes32 orgId, address account) external view returns (bool) {
        return _getUsedVouchesStorage()[orgId][account];
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
     * @notice Get onboarding configuration for POA account creation
     * @return The OnboardingConfig struct
     */
    function getOnboardingConfig() external view returns (OnboardingConfig memory) {
        return _getOnboardingStorage();
    }

    /**
     * @notice Get org's grace period status and limits
     * @param orgId The organization identifier
     * @return inGrace True if in initial grace period
     * @return spendRemaining Spending remaining during grace (0 if not in grace)
     * @return requiresDeposit True if org needs to deposit to access solidarity
     * @return solidarityLimit Current solidarity allocation for org (per 90-day period)
     */
    function getOrgGraceStatus(bytes32 orgId)
        external
        view
        returns (bool inGrace, uint128 spendRemaining, bool requiresDeposit, uint256 solidarityLimit)
    {
        mapping(bytes32 => OrgConfig) storage orgs = _getOrgsStorage();
        mapping(bytes32 => OrgFinancials) storage financials = _getFinancialsStorage();
        GracePeriodConfig storage grace = _getGracePeriodStorage();

        OrgConfig storage config = orgs[orgId];
        OrgFinancials storage org = financials[orgId];

        uint256 graceEndTime = config.registeredAt + (uint256(grace.initialGraceDays) * 1 days);
        inGrace = block.timestamp < graceEndTime;

        if (inGrace) {
            // During grace: track spending limit
            uint128 spendUsed = org.solidarityUsedThisPeriod;
            spendRemaining = spendUsed < grace.maxSpendDuringGrace ? grace.maxSpendDuringGrace - spendUsed : 0;
            requiresDeposit = false;
            solidarityLimit = uint256(grace.maxSpendDuringGrace);
        } else {
            // After grace: check current balance (not cumulative deposits)
            spendRemaining = 0;
            uint256 depositAvailable = org.deposited > org.spent ? org.deposited - org.spent : 0;
            requiresDeposit = depositAvailable < grace.minDepositRequired;
            solidarityLimit = _calculateMatchAllowance(depositAvailable, grace.minDepositRequired);
        }
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

    function _getRulesStorage()
        private
        pure
        returns (mapping(bytes32 => mapping(address => mapping(bytes4 => Rule))) storage $)
    {
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

    function _getUsedVouchesStorage() private pure returns (mapping(bytes32 => mapping(address => bool)) storage $) {
        assembly {
            $.slot := USEDVOUCHES_STORAGE_LOCATION
        }
    }

    function _getOnboardingStorage() private pure returns (OnboardingConfig storage $) {
        assembly {
            $.slot := ONBOARDING_STORAGE_LOCATION
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
        returns (
            uint8 version,
            bytes32 orgId,
            uint8 subjectType,
            bytes20 subjectId,
            uint32 ruleId,
            uint64 mailboxCommit8
        )
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

    /**
     * @notice Validate POA onboarding eligibility for gasless account creation
     * @dev Checks onboarding config and daily rate limits
     * @param account The account being created
     * @param maxCost Maximum gas cost for the operation
     * @return subjectKey The subject key for tracking
     */
    function _validateOnboardingEligibility(address account, uint256 maxCost)
        private
        view
        returns (bytes32 subjectKey)
    {
        OnboardingConfig storage onboarding = _getOnboardingStorage();

        // Check onboarding is enabled
        if (!onboarding.enabled) revert OnboardingDisabled();

        // Check gas cost limit
        if (maxCost > onboarding.maxGasPerCreation) revert GasTooHigh();

        // Check daily rate limit
        uint32 today = uint32(block.timestamp / 1 days);
        if (today == onboarding.currentDay && onboarding.createdToday >= onboarding.dailyCreationLimit) {
            revert OnboardingDailyLimitExceeded();
        }

        // Check solidarity fund has sufficient balance
        SolidarityFund storage solidarity = _getSolidarityStorage();
        if (solidarity.balance < maxCost) revert InsufficientFunds();

        // Subject key for onboarding is based on the account address (natural nonce)
        subjectKey = keccak256(abi.encodePacked(SUBJECT_TYPE_POA_ONBOARDING, bytes20(account)));
    }

    /**
     * @notice Validate vouched eligibility for gasless onboarding
     * @dev Verifies a vouch signature from a voucher hat wearer
     *
     *      Vouch paymasterAndData format (157 bytes total):
     *      [paymaster(20) | version(1) | orgId(32) | subjectType(1) | voucherAddr(20) | ruleId(4) | mailboxCommit(8) | expiry(6) | signature(65)]
     *
     *      The voucher signs: keccak256(abi.encodePacked(orgId, account, expiry, chainId))
     *
     * @param account The account being created (sender)
     * @param orgId The organization identifier
     * @param org The org config (for voucher hat)
     * @param subjectId The voucher address (packed as bytes20)
     * @param paymasterAndData Full paymaster data including vouch signature
     * @return subjectKey The subject key for budget tracking
     */
    function _validateVouchedEligibility(
        address account,
        bytes32 orgId,
        OrgConfig storage org,
        bytes20 subjectId,
        bytes calldata paymasterAndData
    ) private returns (bytes32 subjectKey) {
        // Check voucher hat is configured
        if (org.voucherHatId == 0) revert VoucherHatNotSet();

        // Extract voucher address from subjectId
        address voucher = address(subjectId);

        // Verify voucher wears the voucher hat
        if (!IHats(_getMainStorage().hats).isWearerOfHat(voucher, org.voucherHatId)) {
            revert VoucherNotAuthorized();
        }

        // Check vouch hasn't been used (account address is the natural nonce)
        mapping(bytes32 => mapping(address => bool)) storage usedVouches = _getUsedVouchesStorage();
        if (usedVouches[orgId][account]) revert VouchAlreadyUsed();

        // Extract vouch data from paymasterAndData
        if (paymasterAndData.length < VOUCH_DATA_MIN_LENGTH) revert InvalidPaymasterData();

        uint48 expiry = uint48(bytes6(paymasterAndData[86:92]));
        bytes memory signature = paymasterAndData[92:157];

        // Check expiry
        if (block.timestamp > expiry) revert VouchExpired();

        // Verify signature
        bytes32 vouchHash = keccak256(abi.encodePacked(orgId, account, expiry, block.chainid));
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(vouchHash);

        address recoveredSigner = ECDSA.recover(ethSignedHash, signature);
        if (recoveredSigner != voucher) revert InvalidVouchSignature();

        // Mark vouch as used
        usedVouches[orgId][account] = true;

        // Subject key based on voucher (for budget tracking against voucher's allowance)
        subjectKey = keccak256(abi.encodePacked(SUBJECT_TYPE_VOUCHED, subjectId));

        emit VouchUsed(orgId, account, voucher);
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
            // ERC-4337 account execute patterns (SimpleAccount, PasskeyAccount, etc.)
            selector = bytes4(callData[0:4]);

            // Check for execute(address,uint256,bytes) - 0xb61d27f6
            // Used by SimpleAccount, PasskeyAccount, and most ERC-4337 wallets
            if (selector == 0xb61d27f6 && callData.length >= 0x64) {
                assembly {
                    // Extract target address at offset 0x04
                    target := calldataload(add(callData.offset, 0x04))

                    // Read the bytes data offset pointer at position 0x44
                    // This offset is relative to the start of params (0x04)
                    let dataOffset := calldataload(add(callData.offset, 0x44))

                    // Calculate where the actual bytes data starts:
                    // 0x04 (params start) + dataOffset + 0x20 (skip length field)
                    let dataStart := add(add(0x04, dataOffset), 0x20)

                    // Only extract inner selector if data is within bounds
                    if lt(dataStart, callData.length) {
                        selector := calldataload(add(callData.offset, dataStart))
                    }
                }
                selector = bytes4(selector);
            }
            // Check for executeBatch(address[],bytes[]) - 0x18dfb3c7 (SimpleAccount pattern)
            else if (selector == 0x18dfb3c7) {
                target = userOp.sender;
            }
            // Check for executeBatch(address[],uint256[],bytes[]) - 0x47e1da2a (PasskeyAccount pattern)
            else if (selector == 0x47e1da2a) {
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

    function _checkBudget(bytes32 orgId, bytes32 subjectKey, uint256 maxCost)
        private
        returns (uint32 currentEpochStart)
    {
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

    /**
     * @notice Update onboarding usage and deduct from solidarity fund
     * @dev Called in postOp for POA onboarding operations
     * @param subjectKey The subject key (account address hash)
     * @param actualGasCost Actual gas cost to deduct
     */
    function _updateOnboardingUsage(bytes32 subjectKey, uint256 actualGasCost) private {
        OnboardingConfig storage onboarding = _getOnboardingStorage();
        SolidarityFund storage solidarity = _getSolidarityStorage();

        // Update daily counter
        uint32 today = uint32(block.timestamp / 1 days);
        if (today != onboarding.currentDay) {
            // New day - reset counter
            onboarding.currentDay = today;
            onboarding.createdToday = 1;
        } else {
            onboarding.createdToday++;
        }

        // Deduct from solidarity fund
        solidarity.balance -= uint128(actualGasCost);

        // Extract account address from subject key for event
        // subjectKey = keccak256(abi.encodePacked(SUBJECT_TYPE_POA_ONBOARDING, bytes20(account)))
        // We can't reverse the hash, so we emit the gas cost only
        emit OnboardingAccountCreated(address(0), actualGasCost);
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
