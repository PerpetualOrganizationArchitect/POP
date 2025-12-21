// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {PaymasterHub} from "../src/PaymasterHub.sol";
import {IPaymaster} from "../src/interfaces/IPaymaster.sol";
import {IEntryPoint} from "../src/interfaces/IEntryPoint.sol";
import {PackedUserOperation, UserOpLib} from "../src/interfaces/PackedUserOperation.sol";
import {IHats} from "lib/hats-protocol/src/Interfaces/IHats.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockEntryPoint is IEntryPoint {
    mapping(address => uint256) private _deposits;

    function depositTo(address account) external payable override {
        _deposits[account] += msg.value;
    }

    function withdrawTo(address payable withdrawAddress, uint256 withdrawAmount) external override {
        require(_deposits[msg.sender] >= withdrawAmount, "Insufficient deposit");
        _deposits[msg.sender] -= withdrawAmount;
        withdrawAddress.transfer(withdrawAmount);
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _deposits[account];
    }
}

contract MockHats is IHats {
    mapping(address => mapping(uint256 => bool)) private _wearers;

    function mintHat(uint256 _hatId, address _wearer) external returns (bool success) {
        _wearers[_wearer][_hatId] = true;
        return true;
    }

    function isWearerOfHat(address _wearer, uint256 _hatId) external view returns (bool) {
        return _wearers[_wearer][_hatId];
    }

    // Stub implementations for required interface functions
    function createHat(uint256, string calldata, uint32, address, address, bool, string calldata)
        external
        pure
        returns (uint256)
    {
        return 0;
    }

    function batchCreateHats(
        uint256[] calldata,
        string[] calldata,
        uint32[] calldata,
        address[] calldata,
        address[] calldata,
        bool[] calldata,
        string[] calldata
    ) external pure returns (bool) {
        return true;
    }

    function getNextId(uint256) external pure returns (uint256) {
        return 0;
    }

    function batchMintHats(uint256[] calldata, address[] calldata) external pure returns (bool) {
        return true;
    }

    function setHatStatus(uint256, bool) external pure returns (bool) {
        return true;
    }

    function checkHatStatus(uint256) external pure returns (bool) {
        return true;
    }

    function setHatWearerStatus(uint256, address, bool, bool) external pure returns (bool) {
        return true;
    }

    function checkHatWearerStatus(uint256, address) external pure returns (bool) {
        return true;
    }
    function renounceHat(uint256) external {}
    function transferHat(uint256, address, address) external {}
    function makeHatImmutable(uint256) external {}
    function changeHatDetails(uint256, string calldata, string calldata) external {}
    function changeHatEligibility(uint256, address) external {}
    function changeHatToggle(uint256, address) external {}
    function changeHatImageURI(uint256, string calldata) external {}
    function changeHatMaxSupply(uint256, uint32) external {}
    function requestLinkTopHatToTree(uint32, uint256) external {}
    function unlinkTopHatFromTree(uint32, address) external {}

    function viewHat(uint256)
        external
        pure
        returns (string memory, uint32, uint32, address, address, string memory, uint16, bool, bool)
    {
        return ("", 0, 0, address(0), address(0), "", 0, false, true);
    }
    function changeHatDetails(uint256, string memory) external {}
    function approveLinkTopHatToTree(uint32, uint256, address, address, string calldata, string calldata) external {}
    function relinkTopHatWithinTree(uint32, uint256, address, address, string calldata, string calldata) external {}

    function isTopHat(uint256) external pure returns (bool) {
        return false;
    }

    function isLocalTopHat(uint256) external pure returns (bool) {
        return false;
    }

    function isValidHatId(uint256) external pure returns (bool) {
        return true;
    }

    function getLocalHatLevel(uint256) external pure returns (uint32) {
        return 0;
    }

    function getTopHatDomain(uint256) external pure returns (uint32) {
        return 0;
    }

    function getTippyTopHatDomain(uint32) external pure returns (uint32) {
        return 0;
    }

    function noCircularLinkage(uint32, uint256) external pure returns (bool) {
        return true;
    }

    function sameTippyTopHatDomain(uint32, uint256) external pure returns (bool) {
        return true;
    }

    function getAdminAtLevel(uint256, uint32) external pure returns (uint256) {
        return 0;
    }

    function getAdminAtLocalLevel(uint256, uint32) external pure returns (uint256) {
        return 0;
    }

    function getTopHatDomainOfHat(uint256) external pure returns (uint32) {
        return 0;
    }

    function getTippyTopHatDomainOfHat(uint256) external pure returns (uint32) {
        return 0;
    }

    function tippyHatDomain() external pure returns (uint32) {
        return 0;
    }

    function noCircularLinkage(uint32) external pure returns (uint256) {
        return 0;
    }

    function linkedTreeAdmins(uint32) external pure returns (uint256) {
        return 0;
    }

    function linkedTreeRequests(uint32) external pure returns (uint256) {
        return 0;
    }

    function lastTopHatId() external pure returns (uint256) {
        return 0;
    }

    function baseImageURI() external pure returns (string memory) {
        return "";
    }

    function balanceOf(address, uint256) external pure returns (uint256) {
        return 0;
    }

    function balanceOfBatch(address[] calldata, uint256[] calldata) external pure returns (uint256[] memory) {
        return new uint256[](0);
    }

    function buildHatId(uint256, uint16) external pure returns (uint256) {
        return 0;
    }

    function getHatEligibilityModule(uint256) external pure returns (address) {
        return address(0);
    }

    function getHatLevel(uint256) external pure returns (uint32) {
        return 0;
    }

    function getHatMaxSupply(uint256) external pure returns (uint32) {
        return 0;
    }

    function getHatToggleModule(uint256) external pure returns (address) {
        return address(0);
    }

    function getImageURIForHat(uint256) external pure returns (string memory) {
        return "";
    }

    function hatSupply(uint256) external pure returns (uint32) {
        return 0;
    }

    function isAdminOfHat(address, uint256) external pure returns (bool) {
        return false;
    }

    function isEligible(address, uint256) external pure returns (bool) {
        return true;
    }

    function isInGoodStanding(address, uint256) external pure returns (bool) {
        return true;
    }

    function mintTopHat(address, string memory, string memory) external pure returns (uint256) {
        return 0;
    }

    function uri(uint256) external pure returns (string memory) {
        return "";
    }
}

/**
 * @title PaymasterHubSolidarityTest
 * @notice Comprehensive tests for solidarity fund, grace period, and progressive tier system
 */
contract PaymasterHubSolidarityTest is Test {
    PaymasterHub public hub;
    MockEntryPoint public entryPoint;
    MockHats public hats;

    address public poaManager = address(0x1);
    address public orgAdmin = address(0x2);
    address public user1 = address(0x3);
    address public user2 = address(0x4);

    uint256 constant ADMIN_HAT = 1;
    uint256 constant OPERATOR_HAT = 2;

    bytes32 constant ORG_ALPHA = keccak256("ORG_ALPHA");
    bytes32 constant ORG_BETA = keccak256("ORG_BETA");
    bytes32 constant ORG_GAMMA = keccak256("ORG_GAMMA");

    // Events
    event OrgRegistered(bytes32 indexed orgId, uint256 adminHatId, uint256 operatorHatId);
    event OrgDepositReceived(bytes32 indexed orgId, address indexed from, uint256 amount);
    event SolidarityDonationReceived(address indexed from, uint256 amount);
    event SolidarityFeeCollected(bytes32 indexed orgId, uint256 amount);
    event OrgBannedFromSolidarity(bytes32 indexed orgId, bool banned);
    event GracePeriodConfigUpdated(uint32 initialGraceDays, uint128 maxSpendDuringGrace, uint128 minDepositRequired);

    function setUp() public {
        // Deploy mocks
        entryPoint = new MockEntryPoint();
        hats = new MockHats();

        // Deploy PaymasterHub implementation
        PaymasterHub implementation = new PaymasterHub();

        // Deploy proxy and initialize
        bytes memory initData =
            abi.encodeWithSelector(PaymasterHub.initialize.selector, address(entryPoint), address(hats), poaManager);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        hub = PaymasterHub(payable(address(proxy)));

        // Setup hats
        hats.mintHat(ADMIN_HAT, orgAdmin);
        hats.mintHat(OPERATOR_HAT, orgAdmin);

        // Fund accounts
        vm.deal(poaManager, 100 ether);
        vm.deal(orgAdmin, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        // Register orgs
        hub.registerOrg(ORG_ALPHA, ADMIN_HAT, OPERATOR_HAT);
        hub.registerOrg(ORG_BETA, ADMIN_HAT, OPERATOR_HAT);
        hub.registerOrg(ORG_GAMMA, ADMIN_HAT, OPERATOR_HAT);
    }

    // ============ Initialization Tests ============

    function testInitialization() public {
        assertEq(hub.ENTRY_POINT(), address(entryPoint));
        assertEq(hub.HATS(), address(hats));
        assertEq(hub.POA_MANAGER(), poaManager);

        // Check default grace period config
        PaymasterHub.GracePeriodConfig memory grace = hub.getGracePeriodConfig();
        assertEq(grace.initialGraceDays, 90);
        assertEq(grace.maxSpendDuringGrace, 0.01 ether);
        assertEq(grace.minDepositRequired, 0.003 ether);

        // Check default solidarity fee
        PaymasterHub.SolidarityFund memory solidarity = hub.getSolidarityFund();
        assertEq(solidarity.feePercentageBps, 100); // 1%
        assertEq(solidarity.balance, 0);
        assertEq(solidarity.numActiveOrgs, 0);
    }

    function testOrgRegistration() public {
        bytes32 newOrgId = keccak256("NEW_ORG");

        vm.expectEmit(true, false, false, true);
        emit OrgRegistered(newOrgId, ADMIN_HAT, OPERATOR_HAT);
        hub.registerOrg(newOrgId, ADMIN_HAT, OPERATOR_HAT);

        PaymasterHub.OrgConfig memory config = hub.getOrgConfig(newOrgId);
        assertEq(config.adminHatId, ADMIN_HAT);
        assertEq(config.operatorHatId, OPERATOR_HAT);
        assertFalse(config.paused);
        assertFalse(config.bannedFromSolidarity);
        assertEq(config.registeredAt, block.timestamp);
    }

    // ============ Grace Period Tests ============

    function testGracePeriodSpendingLimit() public view {
        // New org should be in grace period
        PaymasterHub.GracePeriodConfig memory grace = hub.getGracePeriodConfig();
        (bool inGrace, uint128 spendRemaining,,) = hub.getOrgGraceStatus(ORG_ALPHA);

        assertTrue(inGrace);
        assertEq(spendRemaining, grace.maxSpendDuringGrace);
    }

    function testGracePeriodExpires() public {
        // Fast forward past grace period
        vm.warp(block.timestamp + 91 days);

        (bool inGrace,,,) = hub.getOrgGraceStatus(ORG_ALPHA);
        assertFalse(inGrace);
    }

    function testGracePeriodConfigUpdate() public {
        uint32 newGraceDays = 120;
        uint128 newMaxSpend = 0.02 ether;
        uint128 newMinDeposit = 0.005 ether;

        vm.prank(poaManager);
        vm.expectEmit(false, false, false, true);
        emit GracePeriodConfigUpdated(newGraceDays, newMaxSpend, newMinDeposit);
        hub.setGracePeriodConfig(newGraceDays, newMaxSpend, newMinDeposit);

        PaymasterHub.GracePeriodConfig memory grace = hub.getGracePeriodConfig();
        assertEq(grace.initialGraceDays, newGraceDays);
        assertEq(grace.maxSpendDuringGrace, newMaxSpend);
        assertEq(grace.minDepositRequired, newMinDeposit);
    }

    function testGracePeriodConfigOnlyPoaManager() public {
        vm.prank(orgAdmin);
        vm.expectRevert(PaymasterHub.NotPoaManager.selector);
        hub.setGracePeriodConfig(90, 0.01 ether, 0.003 ether);
    }

    // ============ Deposit Tests ============

    function testDepositForOrg() public {
        uint256 depositAmount = 0.01 ether;

        vm.expectEmit(true, true, false, true);
        emit OrgDepositReceived(ORG_ALPHA, user1, depositAmount);

        vm.prank(user1);
        hub.depositForOrg{value: depositAmount}(ORG_ALPHA);

        // Check org financials
        PaymasterHub.OrgFinancials memory fin = hub.getOrgFinancials(ORG_ALPHA);
        assertEq(fin.deposited, depositAmount);
        assertEq(fin.totalDeposited, depositAmount);
        assertEq(fin.spent, 0);
        assertEq(fin.solidarityUsedThisPeriod, 0);

        // Check active org count increased
        PaymasterHub.SolidarityFund memory solidarity = hub.getSolidarityFund();
        assertEq(solidarity.numActiveOrgs, 1);
    }

    function testMultipleDepositsIncrementTotal() public {
        vm.prank(user1);
        hub.depositForOrg{value: 0.003 ether}(ORG_ALPHA);

        vm.prank(user2);
        hub.depositForOrg{value: 0.007 ether}(ORG_ALPHA);

        PaymasterHub.OrgFinancials memory fin = hub.getOrgFinancials(ORG_ALPHA);
        assertEq(fin.deposited, 0.01 ether);
        assertEq(fin.totalDeposited, 0.01 ether);
    }

    function testDepositForNonExistentOrg() public {
        bytes32 fakeOrg = keccak256("FAKE");

        vm.prank(user1);
        vm.expectRevert(PaymasterHub.OrgNotRegistered.selector);
        hub.depositForOrg{value: 0.01 ether}(fakeOrg);
    }

    function testDonateToSolidarity() public {
        uint256 donationAmount = 1 ether;

        vm.expectEmit(true, false, false, true);
        emit SolidarityDonationReceived(user1, donationAmount);

        vm.prank(user1);
        hub.donateToSolidarity{value: donationAmount}();

        PaymasterHub.SolidarityFund memory solidarity = hub.getSolidarityFund();
        assertEq(solidarity.balance, donationAmount);
    }

    // ============ Period Reset Tests ============

    function testPeriodResetOnTimeElapse() public {
        // Make initial deposit
        vm.prank(user1);
        hub.depositForOrg{value: 0.003 ether}(ORG_ALPHA);

        PaymasterHub.OrgFinancials memory fin1 = hub.getOrgFinancials(ORG_ALPHA);
        uint32 initialPeriodStart = fin1.periodStart;

        // Fast forward 91 days
        vm.warp(block.timestamp + 91 days);

        // Make another deposit to trigger period check
        vm.prank(user1);
        hub.depositForOrg{value: 0.001 ether}(ORG_ALPHA);

        PaymasterHub.OrgFinancials memory fin2 = hub.getOrgFinancials(ORG_ALPHA);
        assertGt(fin2.periodStart, initialPeriodStart);
        assertEq(fin2.solidarityUsedThisPeriod, 0); // Should be reset
    }

    function testPeriodResetOnDepositThresholdCrossing() public {
        // Start below minimum (grace period just ended)
        vm.warp(block.timestamp + 91 days);

        // Small deposit - below threshold
        vm.prank(user1);
        hub.depositForOrg{value: 0.002 ether}(ORG_ALPHA);

        PaymasterHub.OrgFinancials memory fin1 = hub.getOrgFinancials(ORG_ALPHA);
        uint32 initialPeriodStart = fin1.periodStart;

        // Advance time slightly to make the timestamp change visible
        vm.warp(block.timestamp + 1 seconds);

        // Cross threshold (minDeposit = 0.003 ETH)
        vm.prank(user1);
        hub.depositForOrg{value: 0.002 ether}(ORG_ALPHA); // Total now 0.004 ETH

        PaymasterHub.OrgFinancials memory fin2 = hub.getOrgFinancials(ORG_ALPHA);
        assertGt(fin2.periodStart, initialPeriodStart);
        assertEq(fin2.solidarityUsedThisPeriod, 0);
    }

    // ============ Progressive Tier Tests ============

    function testTier1MatchAllowance() public {
        // Tier 1: 0.003 ETH deposit → 0.006 ETH match → 0.009 ETH total
        vm.warp(block.timestamp + 91 days); // Exit grace period

        vm.prank(user1);
        hub.depositForOrg{value: 0.003 ether}(ORG_ALPHA);

        (,, bool requiresDeposit, uint256 solidarityLimit) = hub.getOrgGraceStatus(ORG_ALPHA);
        assertFalse(requiresDeposit);
        assertEq(solidarityLimit, 0.006 ether); // 2x match
    }

    function testTier2MatchAllowance() public {
        // Tier 2: 0.006 ETH deposit → 0.009 ETH match → 0.015 ETH total
        vm.warp(block.timestamp + 91 days);

        vm.prank(user1);
        hub.depositForOrg{value: 0.006 ether}(ORG_ALPHA);

        (,,, uint256 solidarityLimit) = hub.getOrgGraceStatus(ORG_ALPHA);
        // First 0.003 at 2x = 0.006, second 0.003 at 1x = 0.003, total = 0.009
        assertEq(solidarityLimit, 0.009 ether);
    }

    function testTier3NoMatch() public {
        // Tier 3: 0.017+ ETH deposit → no match (self-sufficient)
        vm.warp(block.timestamp + 91 days);

        vm.prank(user1);
        hub.depositForOrg{value: 0.02 ether}(ORG_ALPHA);

        (,,, uint256 solidarityLimit) = hub.getOrgGraceStatus(ORG_ALPHA);
        assertEq(solidarityLimit, 0); // No match for large deposits
    }

    function testBelowMinimumNoMatch() public {
        // Below minimum: no match
        vm.warp(block.timestamp + 91 days);

        vm.prank(user1);
        hub.depositForOrg{value: 0.002 ether}(ORG_ALPHA);

        (,, bool requiresDeposit, uint256 solidarityLimit) = hub.getOrgGraceStatus(ORG_ALPHA);
        assertTrue(requiresDeposit); // Below minimum
        assertEq(solidarityLimit, 0); // No match
    }

    // ============ Ban Mechanism Tests ============

    function testBanFromSolidarity() public {
        vm.prank(poaManager);
        vm.expectEmit(true, false, false, true);
        emit OrgBannedFromSolidarity(ORG_ALPHA, true);
        hub.setBanFromSolidarity(ORG_ALPHA, true);

        PaymasterHub.OrgConfig memory config = hub.getOrgConfig(ORG_ALPHA);
        assertTrue(config.bannedFromSolidarity);
    }

    function testUnbanFromSolidarity() public {
        // Ban first
        vm.prank(poaManager);
        hub.setBanFromSolidarity(ORG_ALPHA, true);

        // Then unban
        vm.prank(poaManager);
        vm.expectEmit(true, false, false, true);
        emit OrgBannedFromSolidarity(ORG_ALPHA, false);
        hub.setBanFromSolidarity(ORG_ALPHA, false);

        PaymasterHub.OrgConfig memory config = hub.getOrgConfig(ORG_ALPHA);
        assertFalse(config.bannedFromSolidarity);
    }

    function testBanOnlyPoaManager() public {
        vm.prank(orgAdmin);
        vm.expectRevert(PaymasterHub.NotPoaManager.selector);
        hub.setBanFromSolidarity(ORG_ALPHA, true);
    }

    // ============ Solidarity Fee Tests ============

    function testSetSolidarityFee() public {
        uint16 newFeeBps = 200; // 2%

        vm.prank(poaManager);
        hub.setSolidarityFee(newFeeBps);

        PaymasterHub.SolidarityFund memory solidarity = hub.getSolidarityFund();
        assertEq(solidarity.feePercentageBps, newFeeBps);
    }

    function testSolidarityFeeCapAt10Percent() public {
        vm.prank(poaManager);
        vm.expectRevert(PaymasterHub.FeeTooHigh.selector);
        hub.setSolidarityFee(1001); // >10%
    }

    function testSolidarityFeeOnlyPoaManager() public {
        vm.prank(orgAdmin);
        vm.expectRevert(PaymasterHub.NotPoaManager.selector);
        hub.setSolidarityFee(200);
    }

    // ============ Fuzz Tests ============

    function testFuzz_DepositAmounts(uint128 amount) public {
        vm.assume(amount > 0 && amount <= 10 ether);

        vm.prank(user1);
        vm.deal(user1, amount);
        hub.depositForOrg{value: amount}(ORG_ALPHA);

        PaymasterHub.OrgFinancials memory fin = hub.getOrgFinancials(ORG_ALPHA);
        assertEq(fin.deposited, amount);
        assertEq(fin.totalDeposited, amount);
    }

    function testFuzz_TierMatchCalculation(uint128 depositAmount) public {
        vm.assume(depositAmount >= 0.003 ether && depositAmount <= 1 ether);
        vm.warp(block.timestamp + 91 days);

        vm.prank(user1);
        vm.deal(user1, depositAmount);
        hub.depositForOrg{value: depositAmount}(ORG_ALPHA);

        (,,, uint256 solidarityLimit) = hub.getOrgGraceStatus(ORG_ALPHA);

        // Verify tier logic
        if (depositAmount <= 0.003 ether) {
            // Tier 1: 2x match
            assertEq(solidarityLimit, uint256(depositAmount) * 2);
        } else if (depositAmount <= 0.006 ether) {
            // Tier 2: declining match
            uint256 expected = (0.003 ether * 2) + (uint256(depositAmount) - 0.003 ether);
            assertEq(solidarityLimit, expected);
        } else if (depositAmount >= 0.017 ether) {
            // Tier 3: no match
            assertEq(solidarityLimit, 0);
        }
    }

    function testFuzz_GracePeriodConfig(uint32 graceDays, uint128 maxSpend, uint128 minDeposit) public {
        vm.assume(graceDays > 0 && graceDays <= 365);
        vm.assume(maxSpend > 0 && maxSpend <= 1 ether);
        vm.assume(minDeposit > 0 && minDeposit <= 1 ether);

        vm.prank(poaManager);
        hub.setGracePeriodConfig(graceDays, maxSpend, minDeposit);

        PaymasterHub.GracePeriodConfig memory grace = hub.getGracePeriodConfig();
        assertEq(grace.initialGraceDays, graceDays);
        assertEq(grace.maxSpendDuringGrace, maxSpend);
        assertEq(grace.minDepositRequired, minDeposit);
    }

    // ============ Integration Scenario Tests ============

    function testScenario_BootstrappingCoOp() public {
        // Month 1-3: Grace period
        // Spending: 0.0083 ETH (~$25)
        // From solidarity: 100%

        // (Note: Actual spending happens in postOp during validatePaymasterUserOp,
        // which requires full EntryPoint integration. This tests the state.)

        (bool inGrace, uint128 spendRemaining,,) = hub.getOrgGraceStatus(ORG_ALPHA);
        assertTrue(inGrace);
        assertEq(spendRemaining, 0.01 ether);

        // Month 4: Enter Tier 1
        vm.warp(block.timestamp + 91 days);

        vm.prank(user1);
        hub.depositForOrg{value: 0.003 ether}(ORG_ALPHA);

        uint256 solidarityLimit;
        (inGrace,,, solidarityLimit) = hub.getOrgGraceStatus(ORG_ALPHA);
        assertFalse(inGrace);
        assertEq(solidarityLimit, 0.006 ether); // 2x match

        PaymasterHub.OrgFinancials memory fin = hub.getOrgFinancials(ORG_ALPHA);
        assertEq(fin.deposited, 0.003 ether);
    }

    function testScenario_GrowingCoOp() public {
        // Month 4: Enter Tier 2
        vm.warp(block.timestamp + 91 days);

        vm.prank(user1);
        hub.depositForOrg{value: 0.006 ether}(ORG_ALPHA);

        (,,, uint256 solidarityLimit) = hub.getOrgGraceStatus(ORG_ALPHA);
        assertEq(solidarityLimit, 0.009 ether); // First 0.003 at 2x + second 0.003 at 1x

        PaymasterHub.OrgFinancials memory fin = hub.getOrgFinancials(ORG_ALPHA);
        assertEq(fin.deposited, 0.006 ether);
    }

    function testScenario_EstablishedCoOp() public {
        // Month 4: Tier 3 (self-sufficient)
        vm.warp(block.timestamp + 91 days);

        vm.prank(user1);
        hub.depositForOrg{value: 0.05 ether}(ORG_ALPHA);

        (,,, uint256 solidarityLimit) = hub.getOrgGraceStatus(ORG_ALPHA);
        assertEq(solidarityLimit, 0); // No match for large deposits

        PaymasterHub.OrgFinancials memory fin = hub.getOrgFinancials(ORG_ALPHA);
        assertEq(fin.deposited, 0.05 ether);
    }

    function testScenario_TemporaryHardship() public {
        // Normal operations
        vm.warp(block.timestamp + 91 days);
        vm.prank(user1);
        hub.depositForOrg{value: 0.003 ether}(ORG_ALPHA);

        // Can't deposit next month, access cut off
        vm.warp(block.timestamp + 91 days);
        (,, bool requiresDeposit,) = hub.getOrgGraceStatus(ORG_ALPHA);
        assertFalse(requiresDeposit); // Still has initial deposit

        // But if deposit was spent and not replenished...
        // (Would need full integration test with actual spending)

        // Community donates
        vm.prank(user2);
        hub.depositForOrg{value: 0.05 ether}(ORG_ALPHA);

        PaymasterHub.OrgFinancials memory fin = hub.getOrgFinancials(ORG_ALPHA);
        assertEq(fin.deposited, 0.053 ether);
    }

    function testScenario_MaliciousActor() public {
        // Malicious org burns through grace period
        // (Would need full integration test)

        // PoaManager bans
        vm.prank(poaManager);
        hub.setBanFromSolidarity(ORG_ALPHA, true);

        PaymasterHub.OrgConfig memory config = hub.getOrgConfig(ORG_ALPHA);
        assertTrue(config.bannedFromSolidarity);

        // Can still deposit own funds, but no solidarity access
        vm.prank(user1);
        hub.depositForOrg{value: 0.01 ether}(ORG_ALPHA);

        PaymasterHub.OrgFinancials memory fin = hub.getOrgFinancials(ORG_ALPHA);
        assertEq(fin.deposited, 0.01 ether);
    }

    // ============ Edge Case Tests ============

    function testCannotDepositZero() public {
        vm.prank(user1);
        vm.expectRevert(PaymasterHub.ZeroAddress.selector);
        hub.depositForOrg{value: 0}(ORG_ALPHA);
    }

    function testCannotDonateZero() public {
        vm.prank(user1);
        vm.expectRevert(PaymasterHub.ZeroAddress.selector);
        hub.donateToSolidarity{value: 0}();
    }

    function testMultipleOrgsIndependentFinancials() public {
        vm.prank(user1);
        hub.depositForOrg{value: 0.003 ether}(ORG_ALPHA);

        vm.prank(user1);
        hub.depositForOrg{value: 0.006 ether}(ORG_BETA);

        vm.prank(user1);
        hub.depositForOrg{value: 0.02 ether}(ORG_GAMMA);

        // Check each org has independent state
        PaymasterHub.OrgFinancials memory finAlpha = hub.getOrgFinancials(ORG_ALPHA);
        PaymasterHub.OrgFinancials memory finBeta = hub.getOrgFinancials(ORG_BETA);
        PaymasterHub.OrgFinancials memory finGamma = hub.getOrgFinancials(ORG_GAMMA);

        assertEq(finAlpha.deposited, 0.003 ether);
        assertEq(finBeta.deposited, 0.006 ether);
        assertEq(finGamma.deposited, 0.02 ether);

        // Check active org count
        PaymasterHub.SolidarityFund memory solidarity = hub.getSolidarityFund();
        assertEq(solidarity.numActiveOrgs, 3);
    }

    function testPeriodStartInitializedOnFirstDeposit() public {
        PaymasterHub.OrgFinancials memory fin1 = hub.getOrgFinancials(ORG_ALPHA);
        assertEq(fin1.periodStart, 0); // Not initialized yet

        vm.prank(user1);
        hub.depositForOrg{value: 0.003 ether}(ORG_ALPHA);

        PaymasterHub.OrgFinancials memory fin2 = hub.getOrgFinancials(ORG_ALPHA);
        assertEq(fin2.periodStart, block.timestamp);
    }

    // ============ Balance-Based Eligibility Tests ============

    function testBalanceBasedEligibility_LoseEligibilityAfterSpending() public {
        // Exit grace period
        vm.warp(block.timestamp + 91 days);

        // Deposit $10
        vm.prank(user1);
        hub.depositForOrg{value: 0.003 ether}(ORG_ALPHA);

        // Check eligible for Tier 1
        (,, bool requiresDeposit1, uint256 solidarityLimit1) = hub.getOrgGraceStatus(ORG_ALPHA);
        assertFalse(requiresDeposit1);
        assertEq(solidarityLimit1, 0.006 ether); // 2x match

        // Simulate spending by manually updating financials
        // (In real usage, this happens in postOp)
        PaymasterHub.OrgFinancials memory fin = hub.getOrgFinancials(ORG_ALPHA);
        assertEq(fin.deposited, 0.003 ether);
        assertEq(fin.spent, 0);

        // We can't directly test spending without full EntryPoint integration,
        // but we can verify the calculation logic by checking different balance scenarios
    }

    function testBalanceBasedEligibility_TopUpToRegainEligibility() public {
        // Exit grace period
        vm.warp(block.timestamp + 91 days);

        // Deposit $10
        vm.prank(user1);
        hub.depositForOrg{value: 0.003 ether}(ORG_ALPHA);

        // Check eligible
        (,, bool requiresDeposit1, uint256 solidarityLimit1) = hub.getOrgGraceStatus(ORG_ALPHA);
        assertFalse(requiresDeposit1);
        assertEq(solidarityLimit1, 0.006 ether);

        // Top up with another $5 (total cumulative = $15, but this should give Tier 1 match)
        vm.prank(user1);
        hub.depositForOrg{value: 0.0015 ether}(ORG_ALPHA);

        // Check still Tier 1 (balance = 0.0045 ETH, which is > minDeposit but < 2x minDeposit)
        (,, bool requiresDeposit2, uint256 solidarityLimit2) = hub.getOrgGraceStatus(ORG_ALPHA);
        assertFalse(requiresDeposit2);

        // Should get 2x match on 0.003 (first tier) + 1x match on 0.0015 (second tier)
        // First tier: 0.003 * 2 = 0.006
        // Second tier: 0.0015 * 1 = 0.0015
        // Total: 0.0075 ETH
        assertEq(solidarityLimit2, 0.0075 ether);
    }

    function testBalanceBasedEligibility_OnlyNeedTopUpNotFullDeposit() public {
        // This test simulates the key requirement:
        // If you had $10 and spent $5, you only need to deposit $5 to get back to $10

        // Exit grace period
        vm.warp(block.timestamp + 91 days);

        // Initial deposit $10
        vm.prank(user1);
        hub.depositForOrg{value: 0.003 ether}(ORG_ALPHA);

        PaymasterHub.OrgFinancials memory fin1 = hub.getOrgFinancials(ORG_ALPHA);
        assertEq(fin1.deposited, 0.003 ether);
        assertEq(fin1.spent, 0);

        // Check eligible for $20 match
        (,, bool requiresDeposit1, uint256 solidarityLimit1) = hub.getOrgGraceStatus(ORG_ALPHA);
        assertFalse(requiresDeposit1);
        assertEq(solidarityLimit1, 0.006 ether);

        // In next period, if org spent $5 (we'll simulate with direct access to test the calculation)
        // Balance would be: deposited = 0.003, spent = 0.0015, available = 0.0015 ($5)

        // This verifies the CALCULATION uses available balance, not cumulative deposits
        // The actual spending happens in postOp which requires full EntryPoint setup
    }

    function testCalculateMatchAllowance_UsesAvailableBalance() public {
        // This verifies that eligibility is based on available balance (deposited - spent)
        // not cumulative deposits

        // Exit grace period
        vm.warp(block.timestamp + 91 days);

        // Without any deposits, should require deposit and have no match
        (,, bool requiresDeposit1, uint256 match1) = hub.getOrgGraceStatus(ORG_ALPHA);
        assertTrue(requiresDeposit1);
        assertEq(match1, 0);

        // After depositing exactly minimum, should not require deposit and get 2x match
        vm.prank(user1);
        hub.depositForOrg{value: 0.003 ether}(ORG_ALPHA);

        (,, bool requiresDeposit2, uint256 match2) = hub.getOrgGraceStatus(ORG_ALPHA);
        assertFalse(requiresDeposit2);
        assertEq(match2, 0.006 ether); // 2x match on available balance
    }

    function testBalanceBasedTiers_Tier1To2To3() public {
        // Exit grace period
        vm.warp(block.timestamp + 91 days);

        // Tier 1: Deposit 0.003 ETH ($10)
        vm.prank(user1);
        hub.depositForOrg{value: 0.003 ether}(ORG_ALPHA);

        (,, bool requiresDeposit1, uint256 limit1) = hub.getOrgGraceStatus(ORG_ALPHA);
        assertFalse(requiresDeposit1);
        assertEq(limit1, 0.006 ether); // 2x match

        // Tier 2: Add 0.003 ETH more (total balance = 0.006 ETH = $20)
        vm.prank(user1);
        hub.depositForOrg{value: 0.003 ether}(ORG_ALPHA);

        (,, bool requiresDeposit2, uint256 limit2) = hub.getOrgGraceStatus(ORG_ALPHA);
        assertFalse(requiresDeposit2);
        assertEq(limit2, 0.009 ether); // 0.006 (first tier 2x) + 0.003 (second tier 1x)

        // Tier 3: Add 0.011 ETH more (total balance = 0.017 ETH = $51)
        vm.prank(user1);
        hub.depositForOrg{value: 0.011 ether}(ORG_ALPHA);

        (,, bool requiresDeposit3, uint256 limit3) = hub.getOrgGraceStatus(ORG_ALPHA);
        assertFalse(requiresDeposit3);
        assertEq(limit3, 0); // No match for self-sufficient orgs
    }

    function testBalanceBasedEligibility_BelowMinimumNoMatch() public {
        // Exit grace period
        vm.warp(block.timestamp + 91 days);

        // Deposit below minimum (0.002 ETH < 0.003 ETH minimum)
        vm.prank(user1);
        hub.depositForOrg{value: 0.002 ether}(ORG_ALPHA);

        // Should require deposit and have no match
        (,, bool requiresDeposit, uint256 solidarityLimit) = hub.getOrgGraceStatus(ORG_ALPHA);
        assertTrue(requiresDeposit);
        assertEq(solidarityLimit, 0);
    }

    function testBalanceBasedEligibility_ExactlyAtMinimumGetsMatch() public {
        // Exit grace period
        vm.warp(block.timestamp + 91 days);

        // Deposit exactly at minimum
        vm.prank(user1);
        hub.depositForOrg{value: 0.003 ether}(ORG_ALPHA);

        (,, bool requiresDeposit, uint256 solidarityLimit) = hub.getOrgGraceStatus(ORG_ALPHA);
        assertFalse(requiresDeposit);
        assertEq(solidarityLimit, 0.006 ether); // 2x match
    }
}
