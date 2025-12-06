// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*──────────── forge-std helpers ───────────*/
import "forge-std/Test.sol";
import "forge-std/console.sol";

/*──────────── OpenZeppelin ───────────*/
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

/*──────────── Local contracts ───────────*/
import {PasskeyAccount} from "../src/PasskeyAccount.sol";
import {PasskeyAccountFactory} from "../src/PasskeyAccountFactory.sol";
import {IPasskeyAccount} from "../src/interfaces/IPasskeyAccount.sol";
import {P256Verifier} from "../src/libs/P256Verifier.sol";
import {WebAuthnLib} from "../src/libs/WebAuthnLib.sol";
import {QuickJoin} from "../src/QuickJoin.sol";
import {UniversalAccountRegistry} from "../src/UniversalAccountRegistry.sol";
import {Executor} from "../src/Executor.sol";
import {AccessFactory} from "../src/factories/AccessFactory.sol";
import {ModuleTypes} from "../src/libs/ModuleTypes.sol";
import {PackedUserOperation} from "../src/interfaces/PackedUserOperation.sol";

/*──────────── Hats Protocol ───────────*/
import {IHats} from "@hats-protocol/src/Interfaces/IHats.sol";
import {MockHats} from "./mocks/MockHats.sol";

/*────────────────────── Mock Contracts ──────────────────────*/

/// @notice Mock P256 Precompile that always returns valid
contract MockP256Precompile {
    function verify(bytes32, bytes32, bytes32, bytes32, bytes32) external pure returns (uint256) {
        return 1;
    }

    fallback() external {
        assembly {
            // Return 1 (valid signature)
            mstore(0x00, 1)
            return(0x00, 0x20)
        }
    }
}

/// @notice Mock EntryPoint for testing
contract MockEntryPoint {
    address public account;

    function setAccount(address _account) external {
        account = _account;
    }

    function validateUserOp(
        address accountAddr,
        PackedUserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external returns (uint256) {
        return PasskeyAccount(payable(accountAddr)).validateUserOp(userOp, userOpHash, missingAccountFunds);
    }

    function executeFromEntryPoint(address target, bytes calldata data) external returns (bytes memory) {
        (bool success, bytes memory result) = target.call(data);
        require(success, "EntryPoint call failed");
        return result;
    }
}

/// @notice Mock Executor for testing hat minting
contract MockExecutor {
    mapping(address => uint256[]) public mintedHats;

    function mintHatsForUser(address user, uint256[] calldata hatIds) external {
        for (uint256 i = 0; i < hatIds.length; i++) {
            mintedHats[user].push(hatIds[i]);
        }
    }

    function getMintedHats(address user) external view returns (uint256[] memory) {
        return mintedHats[user];
    }
}

/*────────────────────── Test Contract ──────────────────────*/

contract PasskeyTest is Test {
    /*──────── Constants ────────*/
    bytes32 constant ORG_ID = keccak256("TEST_ORG");
    bytes32 constant CREDENTIAL_ID = keccak256("test_credential_1");
    bytes32 constant CREDENTIAL_ID_2 = keccak256("test_credential_2");

    // Test P256 public key (not real - just for structure testing)
    bytes32 constant PUB_KEY_X = 0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
    bytes32 constant PUB_KEY_Y = 0xfedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321;

    /*──────── State ────────*/
    PasskeyAccount accountImpl;
    PasskeyAccountFactory factoryImpl;
    UpgradeableBeacon accountBeacon;
    UpgradeableBeacon factoryBeacon;
    PasskeyAccountFactory factory;
    MockEntryPoint entryPoint;
    MockExecutor mockExecutor;
    QuickJoin quickJoinImpl;
    UpgradeableBeacon quickJoinBeacon;
    QuickJoin quickJoin;
    UniversalAccountRegistry accountRegistry;
    MockHats hats;

    address owner = address(0x1);
    address guardian = address(0x2);
    address user = address(0x3);
    address attacker = address(0x4);

    /*──────── Events ────────*/
    event CredentialAdded(bytes32 indexed credentialId, bytes32 orgId, uint64 createdAt);
    event CredentialRemoved(bytes32 indexed credentialId);
    event CredentialStatusChanged(bytes32 indexed credentialId, bool active);
    event GuardianUpdated(address indexed oldGuardian, address indexed newGuardian);
    event RecoveryInitiated(
        bytes32 indexed recoveryId, bytes32 credentialId, address indexed initiator, uint48 executeAfter
    );
    event RecoveryCompleted(bytes32 indexed recoveryId, bytes32 indexed credentialId);
    event RecoveryCancelled(bytes32 indexed recoveryId);
    event AccountCreated(address indexed account, bytes32 indexed orgId, bytes32 credentialId, address indexed owner);
    event OrgRegistered(bytes32 indexed orgId, uint8 maxCredentials, address guardian, uint48 recoveryDelay);

    /*──────── Setup ────────*/
    function setUp() public {
        vm.startPrank(owner);

        // Deploy Mock Hats
        hats = new MockHats();

        // Deploy implementations
        accountImpl = new PasskeyAccount();
        factoryImpl = new PasskeyAccountFactory();

        // Deploy beacons
        accountBeacon = new UpgradeableBeacon(address(accountImpl), owner);
        factoryBeacon = new UpgradeableBeacon(address(factoryImpl), owner);

        // Deploy factory via beacon proxy
        bytes memory factoryInitData = abi.encodeWithSelector(
            PasskeyAccountFactory.initialize.selector,
            owner, // executor
            address(accountBeacon) // account beacon
        );
        factory = PasskeyAccountFactory(address(new BeaconProxy(address(factoryBeacon), factoryInitData)));

        // Deploy mock entry point
        entryPoint = new MockEntryPoint();

        // Deploy mock executor
        mockExecutor = new MockExecutor();

        // Deploy account registry
        accountRegistry = new UniversalAccountRegistry();
        accountRegistry.initialize(owner);

        // Register the org in factory
        factory.registerOrg(ORG_ID, 5, guardian, 7 days);

        vm.stopPrank();
    }

    /*════════════════════════════════════════════════════════════════════
                        PASSKEY ACCOUNT FACTORY TESTS
    ════════════════════════════════════════════════════════════════════*/

    function testFactoryInitialization() public view {
        assertEq(factory.executor(), owner);
        assertEq(factory.accountBeacon(), address(accountBeacon));
    }

    function testFactoryRegisterOrg() public {
        vm.startPrank(owner);

        bytes32 newOrgId = keccak256("NEW_ORG");

        vm.expectEmit(true, false, false, true);
        emit OrgRegistered(newOrgId, 10, guardian, 14 days);

        factory.registerOrg(newOrgId, 10, guardian, 14 days);

        PasskeyAccountFactory.OrgConfig memory config = factory.getOrgConfig(newOrgId);
        assertEq(config.maxCredentialsPerAccount, 10);
        assertEq(config.defaultGuardian, guardian);
        assertEq(config.recoveryDelay, 14 days);
        assertTrue(config.enabled);

        vm.stopPrank();
    }

    function testFactoryRegisterOrgUnauthorized() public {
        vm.prank(attacker);
        vm.expectRevert(PasskeyAccountFactory.Unauthorized.selector);
        factory.registerOrg(keccak256("ATTACKER_ORG"), 5, guardian, 7 days);
    }

    function testFactoryCreateAccount() public {
        vm.prank(user);

        vm.expectEmit(true, true, false, true);
        emit AccountCreated(
            factory.getAddress(ORG_ID, CREDENTIAL_ID, PUB_KEY_X, PUB_KEY_Y, 0), ORG_ID, CREDENTIAL_ID, user
        );

        address account = factory.createAccount(ORG_ID, CREDENTIAL_ID, PUB_KEY_X, PUB_KEY_Y, 0);

        assertTrue(account != address(0));
        assertTrue(factory.isDeployedAccount(account));

        PasskeyAccount pa = PasskeyAccount(payable(account));
        assertEq(pa.factory(), address(factory));
        assertEq(pa.guardian(), guardian);

        IPasskeyAccount.PasskeyCredential memory cred = pa.getCredential(CREDENTIAL_ID);
        assertEq(cred.publicKeyX, PUB_KEY_X);
        assertEq(cred.publicKeyY, PUB_KEY_Y);
        assertTrue(cred.active);
    }

    function testFactoryCreateAccountDeterministic() public {
        // Get predicted address
        address predicted = factory.getAddress(ORG_ID, CREDENTIAL_ID, PUB_KEY_X, PUB_KEY_Y, 0);

        // Create account
        vm.prank(user);
        address actual = factory.createAccount(ORG_ID, CREDENTIAL_ID, PUB_KEY_X, PUB_KEY_Y, 0);

        assertEq(actual, predicted);
    }

    function testFactoryCreateAccountSameTwice() public {
        vm.startPrank(user);

        address first = factory.createAccount(ORG_ID, CREDENTIAL_ID, PUB_KEY_X, PUB_KEY_Y, 0);
        address second = factory.createAccount(ORG_ID, CREDENTIAL_ID, PUB_KEY_X, PUB_KEY_Y, 0);

        // Should return same address (idempotent)
        assertEq(first, second);

        vm.stopPrank();
    }

    function testFactoryCreateAccountDisabledOrg() public {
        vm.prank(owner);
        factory.setOrgEnabled(ORG_ID, false);

        vm.prank(user);
        vm.expectRevert(PasskeyAccountFactory.OrgNotEnabled.selector);
        factory.createAccount(ORG_ID, CREDENTIAL_ID, PUB_KEY_X, PUB_KEY_Y, 0);
    }

    function testFactoryCreateAccountUnregisteredOrg() public {
        vm.prank(user);
        vm.expectRevert(PasskeyAccountFactory.OrgNotEnabled.selector);
        factory.createAccount(keccak256("UNKNOWN_ORG"), CREDENTIAL_ID, PUB_KEY_X, PUB_KEY_Y, 0);
    }

    function testFactoryUpdateOrgConfig() public {
        vm.startPrank(owner);

        factory.updateOrgConfig(ORG_ID, 8, address(0x999), 10 days);

        PasskeyAccountFactory.OrgConfig memory config = factory.getOrgConfig(ORG_ID);
        assertEq(config.maxCredentialsPerAccount, 8);
        assertEq(config.defaultGuardian, address(0x999));
        assertEq(config.recoveryDelay, 10 days);

        vm.stopPrank();
    }

    function testFactorySetExecutor() public {
        vm.startPrank(owner);

        address newExecutor = address(0x888);
        factory.setExecutor(newExecutor);

        assertEq(factory.executor(), newExecutor);

        vm.stopPrank();
    }

    function testFactorySetExecutorZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(PasskeyAccountFactory.ZeroAddress.selector);
        factory.setExecutor(address(0));
    }

    /*════════════════════════════════════════════════════════════════════
                        PASSKEY ACCOUNT TESTS
    ════════════════════════════════════════════════════════════════════*/

    function _createAccount() internal returns (PasskeyAccount) {
        vm.prank(user);
        address account = factory.createAccount(ORG_ID, CREDENTIAL_ID, PUB_KEY_X, PUB_KEY_Y, 0);
        return PasskeyAccount(payable(account));
    }

    function testAccountInitialization() public {
        PasskeyAccount account = _createAccount();

        assertEq(account.factory(), address(factory));
        assertEq(account.guardian(), guardian);
        assertGe(account.recoveryDelay(), 1 days); // MIN_RECOVERY_DELAY

        bytes32[] memory credIds = account.getCredentialIds();
        assertEq(credIds.length, 1);
        assertEq(credIds[0], CREDENTIAL_ID);

        IPasskeyAccount.PasskeyCredential memory cred = account.getCredential(CREDENTIAL_ID);
        assertEq(cred.publicKeyX, PUB_KEY_X);
        assertEq(cred.publicKeyY, PUB_KEY_Y);
        assertEq(cred.orgId, ORG_ID);
        assertTrue(cred.active);
        assertEq(cred.signCount, 0);
    }

    function testAccountAddCredentialOnlySelf() public {
        PasskeyAccount account = _createAccount();

        // Try to add credential directly (should fail)
        vm.prank(user);
        vm.expectRevert(IPasskeyAccount.OnlySelf.selector);
        account.addCredential(CREDENTIAL_ID_2, PUB_KEY_X, PUB_KEY_Y, ORG_ID);
    }

    function testAccountAddCredentialViaSelf() public {
        PasskeyAccount account = _createAccount();

        // Simulate a self-call (would normally come from UserOp execution)
        vm.prank(address(account));

        vm.expectEmit(true, false, false, true);
        emit CredentialAdded(CREDENTIAL_ID_2, ORG_ID, uint64(block.timestamp));

        account.addCredential(CREDENTIAL_ID_2, PUB_KEY_X, PUB_KEY_Y, ORG_ID);

        bytes32[] memory credIds = account.getCredentialIds();
        assertEq(credIds.length, 2);

        assertEq(account.getOrgCredentialCount(ORG_ID), 2);
    }

    function testAccountAddCredentialDuplicate() public {
        PasskeyAccount account = _createAccount();

        vm.prank(address(account));
        vm.expectRevert(IPasskeyAccount.CredentialExists.selector);
        account.addCredential(CREDENTIAL_ID, PUB_KEY_X, PUB_KEY_Y, ORG_ID);
    }

    function testAccountRemoveCredential() public {
        PasskeyAccount account = _createAccount();

        // Add a second credential first
        vm.prank(address(account));
        account.addCredential(CREDENTIAL_ID_2, PUB_KEY_X, PUB_KEY_Y, ORG_ID);

        // Now remove the first one
        vm.prank(address(account));

        vm.expectEmit(true, false, false, false);
        emit CredentialRemoved(CREDENTIAL_ID);

        account.removeCredential(CREDENTIAL_ID);

        bytes32[] memory credIds = account.getCredentialIds();
        assertEq(credIds.length, 1);
        assertEq(credIds[0], CREDENTIAL_ID_2);
    }

    function testAccountCannotRemoveLastCredential() public {
        PasskeyAccount account = _createAccount();

        vm.prank(address(account));
        vm.expectRevert(IPasskeyAccount.CannotRemoveLastCredential.selector);
        account.removeCredential(CREDENTIAL_ID);
    }

    function testAccountSetCredentialActive() public {
        PasskeyAccount account = _createAccount();

        vm.prank(address(account));

        vm.expectEmit(true, false, false, true);
        emit CredentialStatusChanged(CREDENTIAL_ID, false);

        account.setCredentialActive(CREDENTIAL_ID, false);

        IPasskeyAccount.PasskeyCredential memory cred = account.getCredential(CREDENTIAL_ID);
        assertFalse(cred.active);
    }

    function testAccountSetGuardian() public {
        PasskeyAccount account = _createAccount();

        address newGuardian = address(0x777);

        vm.prank(address(account));

        vm.expectEmit(true, true, false, false);
        emit GuardianUpdated(guardian, newGuardian);

        account.setGuardian(newGuardian);

        assertEq(account.guardian(), newGuardian);
    }

    function testAccountSetRecoveryDelay() public {
        PasskeyAccount account = _createAccount();

        vm.prank(address(account));
        account.setRecoveryDelay(14 days);

        assertEq(account.recoveryDelay(), 14 days);
    }

    function testAccountSetRecoveryDelayMinimum() public {
        PasskeyAccount account = _createAccount();

        // Try to set below minimum - should be capped
        vm.prank(address(account));
        account.setRecoveryDelay(1 hours);

        assertEq(account.recoveryDelay(), 1 days); // MIN_RECOVERY_DELAY
    }

    /*════════════════════════════════════════════════════════════════════
                        RECOVERY TESTS
    ════════════════════════════════════════════════════════════════════*/

    function testInitiateRecovery() public {
        PasskeyAccount account = _createAccount();

        bytes32 newCredId = keccak256("recovery_credential");
        bytes32 newPubKeyX = keccak256("new_x");
        bytes32 newPubKeyY = keccak256("new_y");

        vm.prank(guardian);
        account.initiateRecovery(newCredId, newPubKeyX, newPubKeyY);

        // Verify recovery request was created
        // Note: Recovery ID is computed from credentialId, timestamp, and sender
    }

    function testInitiateRecoveryUnauthorized() public {
        PasskeyAccount account = _createAccount();

        vm.prank(attacker);
        vm.expectRevert(IPasskeyAccount.OnlyGuardian.selector);
        account.initiateRecovery(keccak256("new_cred"), keccak256("x"), keccak256("y"));
    }

    function testCompleteRecoveryBeforeDelay() public {
        PasskeyAccount account = _createAccount();

        bytes32 newCredId = keccak256("recovery_credential");

        vm.prank(guardian);
        account.initiateRecovery(newCredId, keccak256("x"), keccak256("y"));

        // Get recovery ID (would need to capture from event in real scenario)
        bytes32 recoveryId = keccak256(abi.encodePacked(newCredId, block.timestamp, guardian));

        // Try to complete immediately
        vm.expectRevert(IPasskeyAccount.RecoveryDelayNotPassed.selector);
        account.completeRecovery(recoveryId);
    }

    function testCompleteRecoveryAfterDelay() public {
        PasskeyAccount account = _createAccount();

        bytes32 newCredId = keccak256("recovery_credential");
        bytes32 newPubKeyX = keccak256("new_x");
        bytes32 newPubKeyY = keccak256("new_y");

        vm.prank(guardian);
        account.initiateRecovery(newCredId, newPubKeyX, newPubKeyY);

        bytes32 recoveryId = keccak256(abi.encodePacked(newCredId, block.timestamp, guardian));

        // Warp past recovery delay
        vm.warp(block.timestamp + 7 days + 1);

        vm.expectEmit(true, true, false, false);
        emit RecoveryCompleted(recoveryId, newCredId);

        account.completeRecovery(recoveryId);

        // Verify credential was added
        IPasskeyAccount.PasskeyCredential memory cred = account.getCredential(newCredId);
        assertEq(cred.publicKeyX, newPubKeyX);
        assertEq(cred.publicKeyY, newPubKeyY);
        assertTrue(cred.active);
    }

    function testCancelRecoveryByGuardian() public {
        PasskeyAccount account = _createAccount();

        bytes32 newCredId = keccak256("recovery_credential");

        vm.prank(guardian);
        account.initiateRecovery(newCredId, keccak256("x"), keccak256("y"));

        bytes32 recoveryId = keccak256(abi.encodePacked(newCredId, block.timestamp, guardian));

        vm.prank(guardian);

        vm.expectEmit(true, false, false, false);
        emit RecoveryCancelled(recoveryId);

        account.cancelRecovery(recoveryId);

        IPasskeyAccount.RecoveryRequest memory request = account.getRecoveryRequest(recoveryId);
        assertTrue(request.cancelled);
    }

    function testCancelRecoveryBySelf() public {
        PasskeyAccount account = _createAccount();

        bytes32 newCredId = keccak256("recovery_credential");

        vm.prank(guardian);
        account.initiateRecovery(newCredId, keccak256("x"), keccak256("y"));

        bytes32 recoveryId = keccak256(abi.encodePacked(newCredId, block.timestamp, guardian));

        vm.prank(address(account));
        account.cancelRecovery(recoveryId);

        IPasskeyAccount.RecoveryRequest memory request = account.getRecoveryRequest(recoveryId);
        assertTrue(request.cancelled);
    }

    function testCancelRecoveryUnauthorized() public {
        PasskeyAccount account = _createAccount();

        bytes32 newCredId = keccak256("recovery_credential");

        vm.prank(guardian);
        account.initiateRecovery(newCredId, keccak256("x"), keccak256("y"));

        bytes32 recoveryId = keccak256(abi.encodePacked(newCredId, block.timestamp, guardian));

        vm.prank(attacker);
        vm.expectRevert(IPasskeyAccount.OnlyGuardianOrSelf.selector);
        account.cancelRecovery(recoveryId);
    }

    /*════════════════════════════════════════════════════════════════════
                        EXECUTION TESTS
    ════════════════════════════════════════════════════════════════════*/

    function testExecuteFromSelf() public {
        PasskeyAccount account = _createAccount();

        // Fund the account
        vm.deal(address(account), 1 ether);

        address recipient = address(0x999);
        uint256 amount = 0.1 ether;

        vm.prank(address(account));
        account.execute(recipient, amount, "");

        assertEq(recipient.balance, amount);
    }

    function testExecuteUnauthorized() public {
        PasskeyAccount account = _createAccount();

        vm.deal(address(account), 1 ether);

        vm.prank(attacker);
        vm.expectRevert(IPasskeyAccount.OnlySelf.selector);
        account.execute(address(0x999), 0.1 ether, "");
    }

    function testExecuteBatch() public {
        PasskeyAccount account = _createAccount();

        vm.deal(address(account), 1 ether);

        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory datas = new bytes[](2);

        targets[0] = address(0x111);
        targets[1] = address(0x222);
        values[0] = 0.1 ether;
        values[1] = 0.2 ether;
        datas[0] = "";
        datas[1] = "";

        vm.prank(address(account));
        account.executeBatch(targets, values, datas);

        assertEq(address(0x111).balance, 0.1 ether);
        assertEq(address(0x222).balance, 0.2 ether);
    }

    function testExecuteBatchLengthMismatch() public {
        PasskeyAccount account = _createAccount();

        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](1); // Mismatched
        bytes[] memory datas = new bytes[](2);

        vm.prank(address(account));
        vm.expectRevert(IPasskeyAccount.ArrayLengthMismatch.selector);
        account.executeBatch(targets, values, datas);
    }

    function testReceiveEth() public {
        PasskeyAccount account = _createAccount();

        vm.deal(user, 1 ether);
        vm.prank(user);
        (bool success,) = address(account).call{value: 0.5 ether}("");

        assertTrue(success);
        assertEq(address(account).balance, 0.5 ether);
    }

    /*════════════════════════════════════════════════════════════════════
                        PER-ORG CREDENTIAL LIMIT TESTS
    ════════════════════════════════════════════════════════════════════*/

    function testMaxCredentialsPerOrg() public {
        // Update org config to have max 2 credentials
        vm.prank(owner);
        factory.updateOrgConfig(ORG_ID, 2, guardian, 7 days);

        PasskeyAccount account = _createAccount();

        // Add second credential (should work)
        vm.prank(address(account));
        account.addCredential(CREDENTIAL_ID_2, PUB_KEY_X, PUB_KEY_Y, ORG_ID);

        // Try to add third credential (should fail)
        vm.prank(address(account));
        vm.expectRevert(IPasskeyAccount.MaxCredentialsReached.selector);
        account.addCredential(keccak256("cred3"), PUB_KEY_X, PUB_KEY_Y, ORG_ID);
    }

    function testCredentialsFromDifferentOrgs() public {
        // Register a second org
        vm.prank(owner);
        bytes32 org2 = keccak256("ORG_2");
        factory.registerOrg(org2, 5, guardian, 7 days);

        // Update first org to have max 1 credential
        vm.prank(owner);
        factory.updateOrgConfig(ORG_ID, 1, guardian, 7 days);

        PasskeyAccount account = _createAccount();

        // Can't add more to first org
        vm.prank(address(account));
        vm.expectRevert(IPasskeyAccount.MaxCredentialsReached.selector);
        account.addCredential(CREDENTIAL_ID_2, PUB_KEY_X, PUB_KEY_Y, ORG_ID);

        // But CAN add to second org
        vm.prank(address(account));
        account.addCredential(CREDENTIAL_ID_2, PUB_KEY_X, PUB_KEY_Y, org2);

        assertEq(account.getOrgCredentialCount(ORG_ID), 1);
        assertEq(account.getOrgCredentialCount(org2), 1);
    }

    /*════════════════════════════════════════════════════════════════════
                        QUICK JOIN PASSKEY TESTS
    ════════════════════════════════════════════════════════════════════*/

    function _setupQuickJoin() internal returns (QuickJoin) {
        vm.startPrank(owner);

        // Deploy QuickJoin
        quickJoinImpl = new QuickJoin();
        quickJoinBeacon = new UpgradeableBeacon(address(quickJoinImpl), owner);

        uint256[] memory memberHatIds = new uint256[](0);

        bytes memory qjInitData = abi.encodeWithSelector(
            QuickJoin.initialize.selector,
            owner, // executor (use owner so we can call executor-gated functions)
            address(hats), // hats
            address(accountRegistry), // account registry
            owner, // master deploy
            memberHatIds // member hat ids
        );

        quickJoin = QuickJoin(address(new BeaconProxy(address(quickJoinBeacon), qjInitData)));

        // Configure passkey factory in QuickJoin (requires executor permissions)
        quickJoin.setPasskeyFactory(address(factory));
        quickJoin.setOrgId(ORG_ID);

        vm.stopPrank();

        return quickJoin;
    }

    function testQuickJoinWithPasskey() public {
        QuickJoin qj = _setupQuickJoin();

        vm.prank(user);

        QuickJoin.PasskeyEnrollment memory enrollment = QuickJoin.PasskeyEnrollment({
            credentialId: CREDENTIAL_ID, publicKeyX: PUB_KEY_X, publicKeyY: PUB_KEY_Y, salt: 0
        });

        address account = qj.quickJoinWithPasskey("testuser", enrollment);

        // Verify account was created
        assertTrue(account != address(0));
        assertTrue(factory.isDeployedAccount(account));

        // Verify username was registered
        assertEq(accountRegistry.getUsername(account), "testuser");
    }

    function testQuickJoinWithPasskeyNoUsername() public {
        QuickJoin qj = _setupQuickJoin();

        vm.prank(user);

        QuickJoin.PasskeyEnrollment memory enrollment = QuickJoin.PasskeyEnrollment({
            credentialId: CREDENTIAL_ID, publicKeyX: PUB_KEY_X, publicKeyY: PUB_KEY_Y, salt: 0
        });

        vm.expectRevert(QuickJoin.NoUsername.selector);
        qj.quickJoinWithPasskey("", enrollment);
    }

    function testQuickJoinWithPasskeyFactoryNotSet() public {
        vm.startPrank(owner);

        // Deploy fresh QuickJoin without factory set
        QuickJoin impl = new QuickJoin();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(impl), owner);

        uint256[] memory memberHatIds = new uint256[](0);

        bytes memory qjInitData = abi.encodeWithSelector(
            QuickJoin.initialize.selector,
            owner, // executor
            address(hats),
            address(accountRegistry),
            owner, // master deploy
            memberHatIds
        );

        QuickJoin qj = QuickJoin(address(new BeaconProxy(address(beacon), qjInitData)));

        vm.stopPrank();

        vm.prank(user);

        QuickJoin.PasskeyEnrollment memory enrollment = QuickJoin.PasskeyEnrollment({
            credentialId: CREDENTIAL_ID, publicKeyX: PUB_KEY_X, publicKeyY: PUB_KEY_Y, salt: 0
        });

        vm.expectRevert(QuickJoin.PasskeyFactoryNotSet.selector);
        qj.quickJoinWithPasskey("testuser", enrollment);
    }

    function testQuickJoinWithPasskeyMasterDeploy() public {
        QuickJoin qj = _setupQuickJoin();

        vm.prank(owner); // Master deploy address

        QuickJoin.PasskeyEnrollment memory enrollment = QuickJoin.PasskeyEnrollment({
            credentialId: CREDENTIAL_ID, publicKeyX: PUB_KEY_X, publicKeyY: PUB_KEY_Y, salt: 0
        });

        address account = qj.quickJoinWithPasskeyMasterDeploy("masteruser", enrollment);

        assertTrue(account != address(0));
        assertEq(accountRegistry.getUsername(account), "masteruser");
    }

    function testQuickJoinWithPasskeyMasterDeployUnauthorized() public {
        QuickJoin qj = _setupQuickJoin();

        vm.prank(attacker);

        QuickJoin.PasskeyEnrollment memory enrollment = QuickJoin.PasskeyEnrollment({
            credentialId: CREDENTIAL_ID, publicKeyX: PUB_KEY_X, publicKeyY: PUB_KEY_Y, salt: 0
        });

        vm.expectRevert(QuickJoin.OnlyMasterDeploy.selector);
        qj.quickJoinWithPasskeyMasterDeploy("attackeruser", enrollment);
    }

    /*════════════════════════════════════════════════════════════════════
                        WEBAUTHN LIBRARY TESTS
    ════════════════════════════════════════════════════════════════════*/

    function testWebAuthnAuthDataTooShort() public view {
        WebAuthnLib.WebAuthnAuth memory auth = WebAuthnLib.WebAuthnAuth({
            authenticatorData: new bytes(30), // Too short (min is 37)
            clientDataJSON: new bytes(0),
            challengeIndex: 0,
            typeIndex: 0,
            r: bytes32(0),
            s: bytes32(0)
        });

        bool valid = WebAuthnLib.verify(auth, bytes32(0), PUB_KEY_X, PUB_KEY_Y, false);

        assertFalse(valid);
    }

    function testWebAuthnUserNotPresent() public view {
        // Create auth data with UP flag NOT set
        bytes memory authData = new bytes(37);
        // flags byte at index 32, UP flag is bit 0
        authData[32] = 0x00; // No flags set

        WebAuthnLib.WebAuthnAuth memory auth = WebAuthnLib.WebAuthnAuth({
            authenticatorData: authData,
            clientDataJSON: new bytes(100),
            challengeIndex: 0,
            typeIndex: 0,
            r: bytes32(0),
            s: bytes32(0)
        });

        bool valid = WebAuthnLib.verify(auth, bytes32(0), PUB_KEY_X, PUB_KEY_Y, false);

        assertFalse(valid);
    }

    /*════════════════════════════════════════════════════════════════════
                        VIEW FUNCTION TESTS
    ════════════════════════════════════════════════════════════════════*/

    function testGetMaxCredentialsPerOrg() public view {
        uint8 max = factory.getMaxCredentialsPerOrg(ORG_ID);
        assertEq(max, 5);
    }

    function testGetMaxCredentialsPerOrgUnregistered() public view {
        uint8 max = factory.getMaxCredentialsPerOrg(keccak256("UNREGISTERED"));
        assertEq(max, 5); // Default value
    }

    function testQuickJoinViewFunctions() public {
        QuickJoin qj = _setupQuickJoin();

        assertEq(address(qj.passkeyFactory()), address(factory));
        assertEq(qj.orgId(), ORG_ID);
    }

    /*════════════════════════════════════════════════════════════════════
                        EDGE CASES AND SECURITY TESTS
    ════════════════════════════════════════════════════════════════════*/

    function testFactoryInitializeZeroExecutor() public {
        vm.expectRevert(PasskeyAccountFactory.ZeroAddress.selector);
        new BeaconProxy(
            address(factoryBeacon),
            abi.encodeWithSelector(
                PasskeyAccountFactory.initialize.selector,
                address(0), // Zero executor
                address(accountBeacon)
            )
        );
    }

    function testFactoryInitializeZeroBeacon() public {
        vm.expectRevert(PasskeyAccountFactory.ZeroAddress.selector);
        new BeaconProxy(
            address(factoryBeacon),
            abi.encodeWithSelector(
                PasskeyAccountFactory.initialize.selector,
                owner,
                address(0) // Zero beacon
            )
        );
    }

    function testAccountInitializeZeroFactory() public {
        bytes memory initData = abi.encodeWithSelector(
            PasskeyAccount.initialize.selector,
            address(0), // Zero factory
            CREDENTIAL_ID,
            PUB_KEY_X,
            PUB_KEY_Y,
            ORG_ID,
            guardian,
            7 days
        );

        vm.expectRevert(IPasskeyAccount.ZeroAddress.selector);
        new BeaconProxy(address(accountBeacon), initData);
    }

    function testAccountInitializeZeroPubKey() public {
        bytes memory initData = abi.encodeWithSelector(
            PasskeyAccount.initialize.selector,
            address(factory),
            CREDENTIAL_ID,
            bytes32(0), // Zero public key X
            PUB_KEY_Y,
            ORG_ID,
            guardian,
            7 days
        );

        vm.expectRevert(IPasskeyAccount.InvalidSignature.selector);
        new BeaconProxy(address(accountBeacon), initData);
    }

    function testRemoveCredentialNotFound() public {
        PasskeyAccount account = _createAccount();

        // Add second credential so we can attempt removal
        vm.prank(address(account));
        account.addCredential(CREDENTIAL_ID_2, PUB_KEY_X, PUB_KEY_Y, ORG_ID);

        vm.prank(address(account));
        vm.expectRevert(IPasskeyAccount.CredentialNotFound.selector);
        account.removeCredential(keccak256("nonexistent"));
    }

    function testSetCredentialActiveNotFound() public {
        PasskeyAccount account = _createAccount();

        vm.prank(address(account));
        vm.expectRevert(IPasskeyAccount.CredentialNotFound.selector);
        account.setCredentialActive(keccak256("nonexistent"), false);
    }

    function testInitiateRecoveryExistingCredential() public {
        PasskeyAccount account = _createAccount();

        // Try to initiate recovery with existing credential ID
        vm.prank(guardian);
        vm.expectRevert(IPasskeyAccount.CredentialExists.selector);
        account.initiateRecovery(CREDENTIAL_ID, keccak256("x"), keccak256("y"));
    }

    function testCompleteRecoveryNotPending() public {
        PasskeyAccount account = _createAccount();

        vm.expectRevert(IPasskeyAccount.RecoveryNotPending.selector);
        account.completeRecovery(keccak256("nonexistent_recovery"));
    }

    function testCompleteCancelledRecovery() public {
        PasskeyAccount account = _createAccount();

        bytes32 newCredId = keccak256("recovery_credential");

        vm.prank(guardian);
        account.initiateRecovery(newCredId, keccak256("x"), keccak256("y"));

        bytes32 recoveryId = keccak256(abi.encodePacked(newCredId, block.timestamp, guardian));

        // Cancel the recovery
        vm.prank(guardian);
        account.cancelRecovery(recoveryId);

        // Try to complete after cancelled
        vm.warp(block.timestamp + 7 days + 1);
        vm.expectRevert(IPasskeyAccount.RecoveryNotPending.selector);
        account.completeRecovery(recoveryId);
    }

    function testCancelRecoveryNotPending() public {
        PasskeyAccount account = _createAccount();

        vm.prank(guardian);
        vm.expectRevert(IPasskeyAccount.RecoveryNotPending.selector);
        account.cancelRecovery(keccak256("nonexistent_recovery"));
    }

    function testMultipleOrgCredentialTracking() public {
        // Register multiple orgs
        vm.startPrank(owner);
        bytes32 org1 = keccak256("ORG_1");
        bytes32 org2 = keccak256("ORG_2");
        bytes32 org3 = keccak256("ORG_3");

        factory.registerOrg(org1, 2, guardian, 7 days);
        factory.registerOrg(org2, 2, guardian, 7 days);
        factory.registerOrg(org3, 2, guardian, 7 days);
        vm.stopPrank();

        // Create account for org1
        vm.prank(user);
        address accountAddr = factory.createAccount(org1, CREDENTIAL_ID, PUB_KEY_X, PUB_KEY_Y, 0);
        PasskeyAccount account = PasskeyAccount(payable(accountAddr));

        // Add credential for org2
        vm.prank(address(account));
        account.addCredential(keccak256("cred_org2_1"), PUB_KEY_X, PUB_KEY_Y, org2);

        // Add credential for org3
        vm.prank(address(account));
        account.addCredential(keccak256("cred_org3_1"), PUB_KEY_X, PUB_KEY_Y, org3);

        // Verify counts
        assertEq(account.getOrgCredentialCount(org1), 1);
        assertEq(account.getOrgCredentialCount(org2), 1);
        assertEq(account.getOrgCredentialCount(org3), 1);

        // Total credentials
        assertEq(account.getCredentialIds().length, 3);
    }
}
