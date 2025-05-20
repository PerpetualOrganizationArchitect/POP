// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "../src/QuickJoin.sol";

contract MockMembership is IMembership {
    mapping(address => bool) public minted;

    function quickJoinMint(address newUser) external {
        minted[newUser] = true;
    }
}

contract MockRegistry is IUniversalAccountRegistry {
    mapping(address => string) public usernames;

    function getUsername(address account) external view returns (string memory) {
        return usernames[account];
    }

    function registerAccountQuickJoin(string memory username, address newUser) external {
        usernames[newUser] = username;
    }

    function setUsername(address user, string memory name) external {
        usernames[user] = name;
    }
}

contract QuickJoinTest is Test {
    QuickJoin qj;
    MockMembership membership;
    MockRegistry registry;

    event QuickJoined(address indexed user, bool usernameCreated);
    event QuickJoinedByMaster(address indexed master, address indexed user, bool usernameCreated);

    address executor = address(0x1);
    address master = address(0x2);
    address user1 = address(0x100);
    address user2 = address(0x200);

    bytes32 constant SLOT = 0x566f0545117c69d7a3001f74fa210927792975a5c779e9cbf2876fbc68ef7fa2;

    function setUp() public {
        membership = new MockMembership();
        registry = new MockRegistry();
        qj = new QuickJoin();
        qj.initialize(executor, address(membership), address(registry), master);
    }

    function _storedAddr(uint256 index) internal view returns (address) {
        return address(uint160(uint256(vm.load(address(qj), bytes32(uint256(SLOT) + index)))));
    }

    function testInitializeStoresAddresses() public {
        assertEq(_storedAddr(0), address(membership));
        assertEq(_storedAddr(1), address(registry));
        assertEq(_storedAddr(2), master);
        assertEq(_storedAddr(3), executor);
    }

    function testInitializeZeroAddressReverts() public {
        QuickJoin tmp = new QuickJoin();
        vm.expectRevert(QuickJoin.InvalidAddress.selector);
        tmp.initialize(address(0), address(membership), address(registry), master);
    }

    function testInitializeCannotRunTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        qj.initialize(executor, address(membership), address(registry), master);
    }

    function testUpdateAddresses() public {
        MockMembership m2 = new MockMembership();
        MockRegistry r2 = new MockRegistry();
        address master2 = address(0x3);

        vm.prank(executor);
        qj.updateAddresses(address(m2), address(r2), master2);

        assertEq(_storedAddr(0), address(m2));
        assertEq(_storedAddr(1), address(r2));
        assertEq(_storedAddr(2), master2);
    }

    function testUpdateAddressesUnauthorized() public {
        vm.expectRevert(QuickJoin.Unauthorized.selector);
        qj.updateAddresses(address(membership), address(registry), master);
    }

    function testUpdateAddressesZeroReverts() public {
        vm.prank(executor);
        vm.expectRevert(QuickJoin.InvalidAddress.selector);
        qj.updateAddresses(address(0), address(registry), master);
    }

    function testSetExecutor() public {
        address newExec = address(0x9);
        vm.prank(executor);
        qj.setExecutor(newExec);
        assertEq(_storedAddr(3), newExec);
    }

    function testSetExecutorUnauthorized() public {
        vm.expectRevert(QuickJoin.Unauthorized.selector);
        qj.setExecutor(address(0x9));
    }

    function testSetExecutorZeroReverts() public {
        vm.prank(executor);
        vm.expectRevert(QuickJoin.InvalidAddress.selector);
        qj.setExecutor(address(0));
    }

    function testQuickJoinNoUserRegistersAndMints() public {
        vm.prank(user1);
        qj.quickJoinNoUser("alice");
        assertEq(registry.usernames(user1), "alice");
        assertTrue(membership.minted(user1));
    }

    function testQuickJoinNoUserEmitsEvent() public {
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit QuickJoined(user1, true);
        qj.quickJoinNoUser("alice");
    }

    function testQuickJoinNoUserExistingUsername() public {
        registry.setUsername(user1, "old");
        vm.prank(user1);
        qj.quickJoinNoUser("");
        assertEq(registry.usernames(user1), "old");
        assertTrue(membership.minted(user1));
    }

    function testQuickJoinNoUserEmptyReverts() public {
        vm.prank(user1);
        vm.expectRevert(QuickJoin.NoUsername.selector);
        qj.quickJoinNoUser("");
    }

    function testQuickJoinNoUserTooLong() public {
        string memory longName = string(abi.encodePacked(new bytes(65)));
        vm.prank(user1);
        vm.expectRevert(QuickJoin.UsernameTooLong.selector);
        qj.quickJoinNoUser(longName);
    }

    function testQuickJoinNoUserMaxLen() public {
        string memory name = string(abi.encodePacked(new bytes(64)));
        vm.prank(user1);
        qj.quickJoinNoUser(name);
        assertEq(registry.usernames(user1), name);
    }

    function testQuickJoinWithUser() public {
        registry.setUsername(user1, "bob");
        vm.prank(user1);
        qj.quickJoinWithUser();
        assertTrue(membership.minted(user1));
    }

    function testQuickJoinWithUserEmitsEvent() public {
        registry.setUsername(user1, "bob");
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit QuickJoined(user1, false);
        qj.quickJoinWithUser();
    }

    function testQuickJoinWithUserNoNameReverts() public {
        vm.prank(user1);
        vm.expectRevert(QuickJoin.NoUsername.selector);
        qj.quickJoinWithUser();
    }

    function testQuickJoinNoUserMasterDeployByMaster() public {
        vm.prank(master);
        qj.quickJoinNoUserMasterDeploy("carol", user1);
        assertEq(registry.usernames(user1), "carol");
        assertTrue(membership.minted(user1));
    }

    function testQuickJoinNoUserMasterDeployEmitsEvent() public {
        vm.prank(master);
        vm.expectEmit(true, true, true, true);
        emit QuickJoinedByMaster(master, user1, true);
        qj.quickJoinNoUserMasterDeploy("carol", user1);
    }

    function testQuickJoinNoUserMasterDeployByExecutor() public {
        vm.prank(executor);
        qj.quickJoinNoUserMasterDeploy("dave", user1);
        assertEq(registry.usernames(user1), "dave");
    }

    function testQuickJoinNoUserMasterDeployUnauthorized() public {
        vm.expectRevert(QuickJoin.OnlyMasterDeploy.selector);
        qj.quickJoinNoUserMasterDeploy("x", user1);
    }

    function testQuickJoinNoUserMasterDeployZeroUser() public {
        vm.prank(master);
        vm.expectRevert(QuickJoin.ZeroUser.selector);
        qj.quickJoinNoUserMasterDeploy("x", address(0));
    }

    function testQuickJoinWithUserMasterDeploy() public {
        registry.setUsername(user2, "bob");
        vm.prank(master);
        qj.quickJoinWithUserMasterDeploy(user2);
        assertTrue(membership.minted(user2));
    }

    function testQuickJoinWithUserMasterDeployEmitsEvent() public {
        registry.setUsername(user2, "bob");
        vm.prank(executor);
        vm.expectEmit(true, true, true, true);
        emit QuickJoinedByMaster(executor, user2, false);
        qj.quickJoinWithUserMasterDeploy(user2);
    }

    function testQuickJoinWithUserMasterDeployNoUsername() public {
        vm.prank(master);
        vm.expectRevert(QuickJoin.NoUsername.selector);
        qj.quickJoinWithUserMasterDeploy(user2);
    }

    function testQuickJoinWithUserMasterDeployZeroUser() public {
        vm.prank(master);
        vm.expectRevert(QuickJoin.ZeroUser.selector);
        qj.quickJoinWithUserMasterDeploy(address(0));
    }

    function testQuickJoinWithUserMasterDeployUnauthorized() public {
        registry.setUsername(user1, "bob");
        vm.expectRevert(QuickJoin.OnlyMasterDeploy.selector);
        qj.quickJoinWithUserMasterDeploy(user1);
    }

    function testVersion() public {
        assertEq(qj.version(), "v1");
    }
}
