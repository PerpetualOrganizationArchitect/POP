// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "../src/UniversalAccountRegistry.sol";

/// @dev Mock passkey factory that returns deterministic addresses for testing.
contract MockPasskeyFactory is IPasskeyFactory {
    mapping(bytes32 => address) private _addresses;

    function setAddress(bytes32 credentialId, bytes32 pubKeyX, bytes32 pubKeyY, uint256 salt, address account)
        external
    {
        bytes32 key = keccak256(abi.encode(credentialId, pubKeyX, pubKeyY, salt));
        _addresses[key] = account;
    }

    function getAddress(bytes32 credentialId, bytes32 pubKeyX, bytes32 pubKeyY, uint256 salt)
        external
        view
        returns (address)
    {
        bytes32 key = keccak256(abi.encode(credentialId, pubKeyX, pubKeyY, salt));
        return _addresses[key];
    }
}

contract UARTest is Test {
    UniversalAccountRegistry reg;
    address user = address(1);

    // EIP-712 constants (must match the contract)
    bytes32 private constant _DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant _NAME_HASH = keccak256("UniversalAccountRegistry");
    bytes32 private constant _VERSION_HASH = keccak256("1");
    bytes32 private constant _REGISTER_TYPEHASH =
        keccak256("RegisterAccount(address user,string username,uint256 nonce,uint256 deadline)");
    bytes32 private constant _SET_PROFILE_TYPEHASH =
        keccak256("SetProfileMetadata(address user,bytes32 metadataHash,uint256 nonce,uint256 deadline)");

    // Test private key and derived address
    uint256 private constant SIGNER_PK = 0xA11CE;
    address private signerAddr;

    function setUp() public {
        UniversalAccountRegistry _regImpl = new UniversalAccountRegistry();
        UpgradeableBeacon _regBeacon = new UpgradeableBeacon(address(_regImpl), address(this));
        reg = UniversalAccountRegistry(address(new BeaconProxy(address(_regBeacon), "")));
        reg.initialize(address(this));

        signerAddr = vm.addr(SIGNER_PK);
    }

    /* ═══════════════════ Helpers ═══════════════════ */

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(abi.encode(_DOMAIN_TYPEHASH, _NAME_HASH, _VERSION_HASH, block.chainid, address(reg)));
    }

    function _signRegistration(
        uint256 privateKey,
        address account,
        string memory username,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(_REGISTER_TYPEHASH, account, keccak256(bytes(username)), nonce, deadline)
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    /* ═══════════════════ Existing tests ═══════════════════ */

    function testRegisterAndChange() public {
        vm.prank(user);
        reg.registerAccount("alice");
        assertEq(reg.getUsername(user), "alice");
        vm.prank(user);
        reg.changeUsername("bob");
        assertEq(reg.getUsername(user), "bob");
    }

    function testDeleteAccount() public {
        vm.prank(user);
        reg.registerAccount("alice");
        vm.prank(user);
        reg.deleteAccount();
        assertEq(reg.getUsername(user), "");
    }

    function testRegisterBatchOnlyOwner() public {
        address random = address(0x99);
        address[] memory users = new address[](1);
        users[0] = address(0x50);
        string[] memory names = new string[](1);
        names[0] = "user1";

        vm.prank(random);
        vm.expectRevert();
        reg.registerBatch(users, names);
    }

    /* ═══════════════════ registerAccountBySig tests ═══════════════════ */

    function testRegisterBySig() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = 0;
        bytes memory sig = _signRegistration(SIGNER_PK, signerAddr, "alice", nonce, deadline);

        // Sponsor (not the signer) submits the tx
        address sponsor = address(0xBEEF);
        vm.prank(sponsor);
        reg.registerAccountBySig(signerAddr, "alice", deadline, nonce, sig);

        assertEq(reg.getUsername(signerAddr), "alice");
        assertEq(reg.nonces(signerAddr), 1);
    }

    function testRegisterBySigExpired() public {
        uint256 deadline = block.timestamp - 1; // already expired
        uint256 nonce = 0;
        bytes memory sig = _signRegistration(SIGNER_PK, signerAddr, "alice", nonce, deadline);

        vm.expectRevert(UniversalAccountRegistry.SignatureExpired.selector);
        reg.registerAccountBySig(signerAddr, "alice", deadline, nonce, sig);
    }

    function testRegisterBySigBadNonce() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 wrongNonce = 42;
        bytes memory sig = _signRegistration(SIGNER_PK, signerAddr, "alice", wrongNonce, deadline);

        vm.expectRevert(UniversalAccountRegistry.InvalidNonce.selector);
        reg.registerAccountBySig(signerAddr, "alice", deadline, wrongNonce, sig);
    }

    function testRegisterBySigWrongSigner() public {
        // Sign with a different key than the claimed user
        uint256 differentPK = 0xB0B;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = 0;
        bytes memory sig = _signRegistration(differentPK, signerAddr, "alice", nonce, deadline);

        vm.expectRevert(UniversalAccountRegistry.InvalidSigner.selector);
        reg.registerAccountBySig(signerAddr, "alice", deadline, nonce, sig);
    }

    function testRegisterBySigReplay() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = 0;
        bytes memory sig = _signRegistration(SIGNER_PK, signerAddr, "alice", nonce, deadline);

        reg.registerAccountBySig(signerAddr, "alice", deadline, nonce, sig);

        // Same sig, same nonce — should fail with InvalidNonce (nonce already incremented)
        vm.expectRevert(UniversalAccountRegistry.InvalidNonce.selector);
        reg.registerAccountBySig(signerAddr, "alice2", deadline, nonce, sig);
    }

    function testRegisterBySigBadUsername() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = 0;
        // Username with spaces is invalid
        bytes memory sig = _signRegistration(SIGNER_PK, signerAddr, "bad name", nonce, deadline);

        vm.expectRevert(UniversalAccountRegistry.InvalidChars.selector);
        reg.registerAccountBySig(signerAddr, "bad name", deadline, nonce, sig);
    }

    function testRegisterBySigDuplicateUsername() public {
        // Register "alice" for a different user first
        vm.prank(user);
        reg.registerAccount("alice");

        // Try to register "alice" via sig for signerAddr
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = 0;
        bytes memory sig = _signRegistration(SIGNER_PK, signerAddr, "alice", nonce, deadline);

        vm.expectRevert(UniversalAccountRegistry.UsernameTaken.selector);
        reg.registerAccountBySig(signerAddr, "alice", deadline, nonce, sig);
    }

    function testRegisterBySigUserAlreadyRegistered() public {
        // Register signerAddr first
        vm.prank(signerAddr);
        reg.registerAccount("first");

        // Try to register again via sig
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = 0;
        bytes memory sig = _signRegistration(SIGNER_PK, signerAddr, "second", nonce, deadline);

        vm.expectRevert(UniversalAccountRegistry.AccountExists.selector);
        reg.registerAccountBySig(signerAddr, "second", deadline, nonce, sig);
    }

    /* ═══════════════════ View function tests ═══════════════════ */

    function testNoncesInitialZero() public view {
        assertEq(reg.nonces(signerAddr), 0);
    }

    function testNoncesIncrementAfterBySig() public {
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signRegistration(SIGNER_PK, signerAddr, "alice", 0, deadline);
        reg.registerAccountBySig(signerAddr, "alice", deadline, 0, sig);
        assertEq(reg.nonces(signerAddr), 1);
    }

    function testDomainSeparator() public view {
        bytes32 expected = _domainSeparator();
        assertEq(reg.DOMAIN_SEPARATOR(), expected);
    }

    /* ═══════════════════ Passkey factory config tests ═══════════════════ */

    function testSetPasskeyFactory() public {
        address factory = address(0xFACE);
        reg.setPasskeyFactory(factory);
        assertEq(reg.passkeyFactory(), factory);
    }

    function testSetPasskeyFactoryOnlyOwner() public {
        vm.prank(address(0x99));
        vm.expectRevert();
        reg.setPasskeyFactory(address(0xFACE));
    }

    function testRegisterByPasskeySigNoFactory() public {
        WebAuthnLib.WebAuthnAuth memory auth;
        vm.expectRevert(UniversalAccountRegistry.PasskeyFactoryNotSet.selector);
        reg.registerAccountByPasskeySig(
            bytes32(uint256(1)),
            bytes32(uint256(2)),
            bytes32(uint256(3)),
            0,
            "alice",
            block.timestamp + 1 hours,
            0,
            auth
        );
    }

    /* ═══════════════════ Username release tests (L-01 fix) ═══════════════════ */

    function testDeleteAccountReleasesUsername() public {
        // Register and then delete
        vm.prank(user);
        reg.registerAccount("alice");
        vm.prank(user);
        reg.deleteAccount();

        // Username should now be available for re-registration
        address user2 = address(0x42);
        vm.prank(user2);
        reg.registerAccount("alice");
        assertEq(reg.getUsername(user2), "alice");
    }

    function testChangeUsernameReleasesOldName() public {
        // Register "alice" then change to "bob"
        vm.prank(user);
        reg.registerAccount("alice");
        vm.prank(user);
        reg.changeUsername("bob");
        assertEq(reg.getUsername(user), "bob");

        // "alice" should now be available for someone else
        address user2 = address(0x42);
        vm.prank(user2);
        reg.registerAccount("alice");
        assertEq(reg.getUsername(user2), "alice");
    }

    function testDeleteAndReRegisterSameAddress() public {
        // Register, delete, then re-register with a new name
        vm.prank(user);
        reg.registerAccount("alice");
        vm.prank(user);
        reg.deleteAccount();

        vm.prank(user);
        reg.registerAccount("bob");
        assertEq(reg.getUsername(user), "bob");
    }

    function testDeleteAndReRegisterSameName() public {
        // Register, delete, then re-register the exact same name
        vm.prank(user);
        reg.registerAccount("alice");
        vm.prank(user);
        reg.deleteAccount();

        vm.prank(user);
        reg.registerAccount("alice");
        assertEq(reg.getUsername(user), "alice");
    }

    function testCannotGriefByBurningUsernames() public {
        // Attacker registers "admin" and deletes it -- name should be reusable
        address attacker = address(0xBAD);
        vm.prank(attacker);
        reg.registerAccount("admin");
        vm.prank(attacker);
        reg.deleteAccount();

        // Legitimate user can now claim "admin"
        address legitimate = address(0x600D);
        vm.prank(legitimate);
        reg.registerAccount("admin");
        assertEq(reg.getUsername(legitimate), "admin");
    }

    /* ═══════════════════ Profile Metadata tests ═══════════════════ */

    function _signProfileMetadata(
        uint256 privateKey,
        address account,
        bytes32 metadataHash,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(abi.encode(_SET_PROFILE_TYPEHASH, account, metadataHash, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function testSetProfileMetadata() public {
        vm.prank(user);
        reg.registerAccount("alice");

        bytes32 hash = keccak256("ipfs-cid-hash");
        vm.prank(user);
        reg.setProfileMetadata(hash);

        assertEq(reg.getProfileMetadata(user), hash);
    }

    function testSetProfileMetadataRequiresAccount() public {
        bytes32 hash = keccak256("ipfs-cid-hash");
        vm.prank(user);
        vm.expectRevert(UniversalAccountRegistry.AccountUnknown.selector);
        reg.setProfileMetadata(hash);
    }

    function testSetProfileMetadataUpdate() public {
        vm.prank(user);
        reg.registerAccount("alice");

        bytes32 hash1 = keccak256("first");
        vm.prank(user);
        reg.setProfileMetadata(hash1);
        assertEq(reg.getProfileMetadata(user), hash1);

        bytes32 hash2 = keccak256("second");
        vm.prank(user);
        reg.setProfileMetadata(hash2);
        assertEq(reg.getProfileMetadata(user), hash2);
    }

    function testSetProfileMetadataBySig() public {
        // Register the signer first
        vm.prank(signerAddr);
        reg.registerAccount("alice");

        bytes32 metadataHash = keccak256("ipfs-cid-hash");
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = 0;
        bytes memory sig = _signProfileMetadata(SIGNER_PK, signerAddr, metadataHash, nonce, deadline);

        address sponsor = address(0xBEEF);
        vm.prank(sponsor);
        reg.setProfileMetadataBySig(signerAddr, metadataHash, deadline, nonce, sig);

        assertEq(reg.getProfileMetadata(signerAddr), metadataHash);
        assertEq(reg.nonces(signerAddr), 1);
    }

    function testSetProfileMetadataBySigExpired() public {
        vm.prank(signerAddr);
        reg.registerAccount("alice");

        bytes32 metadataHash = keccak256("ipfs-cid-hash");
        uint256 deadline = block.timestamp - 1;
        bytes memory sig = _signProfileMetadata(SIGNER_PK, signerAddr, metadataHash, 0, deadline);

        vm.expectRevert(UniversalAccountRegistry.SignatureExpired.selector);
        reg.setProfileMetadataBySig(signerAddr, metadataHash, deadline, 0, sig);
    }

    function testSetProfileMetadataBySigRequiresAccount() public {
        bytes32 metadataHash = keccak256("ipfs-cid-hash");
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signProfileMetadata(SIGNER_PK, signerAddr, metadataHash, 0, deadline);

        vm.expectRevert(UniversalAccountRegistry.AccountUnknown.selector);
        reg.setProfileMetadataBySig(signerAddr, metadataHash, deadline, 0, sig);
    }

    function testSetProfileMetadataBySigWrongSigner() public {
        vm.prank(signerAddr);
        reg.registerAccount("alice");

        uint256 differentPK = 0xB0B;
        bytes32 metadataHash = keccak256("ipfs-cid-hash");
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signProfileMetadata(differentPK, signerAddr, metadataHash, 0, deadline);

        vm.expectRevert(UniversalAccountRegistry.InvalidSigner.selector);
        reg.setProfileMetadataBySig(signerAddr, metadataHash, deadline, 0, sig);
    }

    function testSetProfileMetadataEmitsEvent() public {
        vm.prank(user);
        reg.registerAccount("alice");

        bytes32 hash = keccak256("ipfs-cid-hash");
        vm.expectEmit(true, false, false, true);
        emit UniversalAccountRegistry.ProfileMetadataUpdated(user, hash);
        vm.prank(user);
        reg.setProfileMetadata(hash);
    }

    function testGetProfileMetadataDefault() public view {
        assertEq(reg.getProfileMetadata(user), bytes32(0));
    }

    function testSetProfileMetadataBySigReplay() public {
        vm.prank(signerAddr);
        reg.registerAccount("alice");

        bytes32 metadataHash = keccak256("ipfs-cid-hash");
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory sig = _signProfileMetadata(SIGNER_PK, signerAddr, metadataHash, 0, deadline);

        reg.setProfileMetadataBySig(signerAddr, metadataHash, deadline, 0, sig);

        // Replay should fail with InvalidNonce (nonce now 1)
        vm.expectRevert(UniversalAccountRegistry.InvalidNonce.selector);
        reg.setProfileMetadataBySig(signerAddr, metadataHash, deadline, 0, sig);
    }

    function testSetProfileMetadataToZero() public {
        vm.prank(user);
        reg.registerAccount("alice");

        bytes32 hash = keccak256("something");
        vm.prank(user);
        reg.setProfileMetadata(hash);
        assertEq(reg.getProfileMetadata(user), hash);

        // Clear profile by setting to zero
        vm.prank(user);
        reg.setProfileMetadata(bytes32(0));
        assertEq(reg.getProfileMetadata(user), bytes32(0));
    }

    function testDeleteAccountClearsProfileMetadata() public {
        vm.prank(user);
        reg.registerAccount("alice");

        bytes32 hash = keccak256("ipfs-cid-hash");
        vm.prank(user);
        reg.setProfileMetadata(hash);
        assertEq(reg.getProfileMetadata(user), hash);

        // Delete account should also clear profile metadata
        vm.prank(user);
        reg.deleteAccount();
        assertEq(reg.getProfileMetadata(user), bytes32(0));
    }

    function testDeleteDoesNotLeakMetadataToNewUser() public {
        // Alice sets profile metadata then deletes account
        vm.prank(user);
        reg.registerAccount("alice");
        vm.prank(user);
        reg.setProfileMetadata(keccak256("alice-profile"));
        vm.prank(user);
        reg.deleteAccount();

        // Bob registers same username — should NOT see Alice's metadata
        address bob = address(0x42);
        vm.prank(bob);
        reg.registerAccount("alice");
        assertEq(reg.getProfileMetadata(bob), bytes32(0));
    }

    function testChangeUsernamePreservesProfileMetadata() public {
        vm.prank(user);
        reg.registerAccount("alice");

        bytes32 hash = keccak256("my-profile");
        vm.prank(user);
        reg.setProfileMetadata(hash);

        vm.prank(user);
        reg.changeUsername("bob");

        // Profile metadata should survive a username change
        assertEq(reg.getProfileMetadata(user), hash);
        assertEq(reg.getUsername(user), "bob");
    }

    function testNonceSharedBetweenRegisterAndProfile() public {
        // Register via BySig consumes nonce 0
        uint256 deadline = block.timestamp + 1 hours;
        bytes memory regSig = _signRegistration(SIGNER_PK, signerAddr, "alice", 0, deadline);
        reg.registerAccountBySig(signerAddr, "alice", deadline, 0, regSig);
        assertEq(reg.nonces(signerAddr), 1);

        // Profile BySig must use nonce 1 (not 0)
        bytes32 metadataHash = keccak256("profile");
        bytes memory profileSig = _signProfileMetadata(SIGNER_PK, signerAddr, metadataHash, 1, deadline);
        reg.setProfileMetadataBySig(signerAddr, metadataHash, deadline, 1, profileSig);
        assertEq(reg.nonces(signerAddr), 2);
        assertEq(reg.getProfileMetadata(signerAddr), metadataHash);
    }

    function testConsecutiveProfileBySigUpdates() public {
        vm.prank(signerAddr);
        reg.registerAccount("alice");

        uint256 deadline = block.timestamp + 1 hours;

        // First update (nonce 0)
        bytes32 hash1 = keccak256("profile-v1");
        bytes memory sig1 = _signProfileMetadata(SIGNER_PK, signerAddr, hash1, 0, deadline);
        reg.setProfileMetadataBySig(signerAddr, hash1, deadline, 0, sig1);
        assertEq(reg.getProfileMetadata(signerAddr), hash1);
        assertEq(reg.nonces(signerAddr), 1);

        // Second update (nonce 1)
        bytes32 hash2 = keccak256("profile-v2");
        bytes memory sig2 = _signProfileMetadata(SIGNER_PK, signerAddr, hash2, 1, deadline);
        reg.setProfileMetadataBySig(signerAddr, hash2, deadline, 1, sig2);
        assertEq(reg.getProfileMetadata(signerAddr), hash2);
        assertEq(reg.nonces(signerAddr), 2);
    }

    function testSetProfileMetadataBySigBadNonce() public {
        vm.prank(signerAddr);
        reg.registerAccount("alice");

        bytes32 metadataHash = keccak256("ipfs-cid");
        uint256 deadline = block.timestamp + 1 hours;
        uint256 wrongNonce = 42;
        bytes memory sig = _signProfileMetadata(SIGNER_PK, signerAddr, metadataHash, wrongNonce, deadline);

        vm.expectRevert(UniversalAccountRegistry.InvalidNonce.selector);
        reg.setProfileMetadataBySig(signerAddr, metadataHash, deadline, wrongNonce, sig);
    }

    function testSetProfileMetadataBySigDeadlineExact() public {
        // block.timestamp > deadline reverts, so timestamp == deadline should pass
        vm.prank(signerAddr);
        reg.registerAccount("alice");

        bytes32 metadataHash = keccak256("exact-deadline");
        uint256 deadline = block.timestamp; // exactly now
        bytes memory sig = _signProfileMetadata(SIGNER_PK, signerAddr, metadataHash, 0, deadline);

        // Should NOT revert — condition is strictly greater than
        reg.setProfileMetadataBySig(signerAddr, metadataHash, deadline, 0, sig);
        assertEq(reg.getProfileMetadata(signerAddr), metadataHash);
    }

    function testIndependentProfileMetadataPerUser() public {
        address alice = address(0x10);
        address bob = address(0x20);

        vm.prank(alice);
        reg.registerAccount("alice");
        vm.prank(bob);
        reg.registerAccount("bob");

        bytes32 aliceHash = keccak256("alice-profile");
        bytes32 bobHash = keccak256("bob-profile");

        vm.prank(alice);
        reg.setProfileMetadata(aliceHash);
        vm.prank(bob);
        reg.setProfileMetadata(bobHash);

        assertEq(reg.getProfileMetadata(alice), aliceHash);
        assertEq(reg.getProfileMetadata(bob), bobHash);

        // Updating Alice shouldn't affect Bob
        vm.prank(alice);
        reg.setProfileMetadata(keccak256("alice-v2"));
        assertEq(reg.getProfileMetadata(bob), bobHash);
    }

    function testSetProfileMetadataAfterDeleteReverts() public {
        vm.prank(user);
        reg.registerAccount("alice");
        vm.prank(user);
        reg.setProfileMetadata(keccak256("profile"));
        vm.prank(user);
        reg.deleteAccount();

        // Should revert — account no longer exists
        vm.prank(user);
        vm.expectRevert(UniversalAccountRegistry.AccountUnknown.selector);
        reg.setProfileMetadata(keccak256("new-profile"));
    }

    function testSetProfileMetadataByPasskeySigNoFactory() public {
        WebAuthnLib.WebAuthnAuth memory auth;
        vm.expectRevert(UniversalAccountRegistry.PasskeyFactoryNotSet.selector);
        reg.setProfileMetadataByPasskeySig(
            bytes32(uint256(1)),
            bytes32(uint256(2)),
            bytes32(uint256(3)),
            0,
            keccak256("metadata"),
            block.timestamp + 1 hours,
            0,
            auth
        );
    }
}
