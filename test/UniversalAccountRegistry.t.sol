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
}
