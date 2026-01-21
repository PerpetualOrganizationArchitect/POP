// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "../src/QuickJoin.sol";
import "./mocks/MockHats.sol";

contract MockExecutorHatMinter {
    MockHats public hats;

    constructor() {
        hats = new MockHats();
    }

    function mintHatsForUser(address user, uint256[] calldata hatIds) external {
        for (uint256 i = 0; i < hatIds.length; i++) {
            hats.mintHat(hatIds[i], user);
        }
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
    MockHats hats;
    MockRegistry registry;
    MockExecutorHatMinter mockExecutor;

    event QuickJoined(address indexed user, bool usernameCreated, uint256[] hatIds);
    event QuickJoinedByMaster(address indexed master, address indexed user, bool usernameCreated, uint256[] hatIds);

    address executor = address(0x1);
    address master = address(0x2);
    address user1 = address(0x100);
    address user2 = address(0x200);

    uint256 constant DEFAULT_HAT_ID = 1;
    bytes32 constant SLOT = 0x566f0545117c69d7a3001f74fa210927792975a5c779e9cbf2876fbc68ef7fa2;

    function setUp() public {
        hats = new MockHats();
        registry = new MockRegistry();
        mockExecutor = new MockExecutorHatMinter();
        qj = new QuickJoin();

        uint256[] memory memberHats = new uint256[](1);
        memberHats[0] = DEFAULT_HAT_ID;

        qj.initialize(address(mockExecutor), address(hats), address(registry), master, memberHats);
    }

    function _storedAddr(uint256 index) internal view returns (address) {
        return address(uint160(uint256(vm.load(address(qj), bytes32(uint256(SLOT) + index)))));
    }

    function testInitializeStoresAddresses() public {
        assertEq(_storedAddr(0), address(hats));
        assertEq(_storedAddr(1), address(registry));
        assertEq(_storedAddr(2), master);
        assertEq(_storedAddr(3), address(mockExecutor));
    }

    function testInitializeZeroAddressReverts() public {
        QuickJoin tmp = new QuickJoin();
        uint256[] memory memberHats = new uint256[](1);
        memberHats[0] = DEFAULT_HAT_ID;
        vm.expectRevert(QuickJoin.InvalidAddress.selector);
        tmp.initialize(address(0), address(hats), address(registry), master, memberHats);
    }

    function testInitializeCannotRunTwice() public {
        uint256[] memory memberHats = new uint256[](1);
        memberHats[0] = DEFAULT_HAT_ID;
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        qj.initialize(address(mockExecutor), address(hats), address(registry), master, memberHats);
    }

    function testUpdateAddresses() public {
        MockHats h2 = new MockHats();
        MockRegistry r2 = new MockRegistry();
        address master2 = address(0x3);

        vm.prank(address(mockExecutor));
        qj.updateAddresses(address(h2), address(r2), master2);

        assertEq(_storedAddr(0), address(h2));
        assertEq(_storedAddr(1), address(r2));
        assertEq(_storedAddr(2), master2);
    }

    function testUpdateAddressesUnauthorized() public {
        vm.expectRevert(QuickJoin.Unauthorized.selector);
        qj.updateAddresses(address(hats), address(registry), master);
    }

    function testUpdateAddressesZeroReverts() public {
        vm.prank(address(mockExecutor));
        vm.expectRevert(QuickJoin.InvalidAddress.selector);
        qj.updateAddresses(address(0), address(registry), master);
    }

    function testSetExecutor() public {
        address newExec = address(0x9);
        vm.prank(address(mockExecutor));
        qj.setExecutor(newExec);
        assertEq(_storedAddr(3), newExec);
    }

    function testSetExecutorUnauthorized() public {
        vm.expectRevert(QuickJoin.Unauthorized.selector);
        qj.setExecutor(address(0x9));
    }

    function testSetExecutorZeroReverts() public {
        vm.prank(address(mockExecutor));
        vm.expectRevert(QuickJoin.InvalidAddress.selector);
        qj.setExecutor(address(0));
    }

    function testQuickJoinNoUserRegistersAndMints() public {
        vm.prank(user1);
        qj.quickJoinNoUser("alice");
        assertEq(registry.usernames(user1), "alice");
        assertTrue(mockExecutor.hats().isWearerOfHat(user1, DEFAULT_HAT_ID));
    }

    function testQuickJoinNoUserEmitsEvent() public {
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        uint256[] memory expectedHats = new uint256[](1);
        expectedHats[0] = DEFAULT_HAT_ID;
        emit QuickJoined(user1, true, expectedHats);
        qj.quickJoinNoUser("alice");
    }

    function testQuickJoinNoUserExistingUsername() public {
        registry.setUsername(user1, "old");
        vm.prank(user1);
        qj.quickJoinNoUser("");
        assertEq(registry.usernames(user1), "old");
        assertTrue(mockExecutor.hats().isWearerOfHat(user1, DEFAULT_HAT_ID));
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
        assertTrue(mockExecutor.hats().isWearerOfHat(user1, DEFAULT_HAT_ID));
    }

    function testQuickJoinWithUserEmitsEvent() public {
        registry.setUsername(user1, "bob");
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        uint256[] memory expectedHats = new uint256[](1);
        expectedHats[0] = DEFAULT_HAT_ID;
        emit QuickJoined(user1, false, expectedHats);
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
        assertTrue(mockExecutor.hats().isWearerOfHat(user1, DEFAULT_HAT_ID));
    }

    function testQuickJoinNoUserMasterDeployEmitsEvent() public {
        vm.prank(master);
        vm.expectEmit(true, true, true, true);
        uint256[] memory expectedHats = new uint256[](1);
        expectedHats[0] = DEFAULT_HAT_ID;
        emit QuickJoinedByMaster(master, user1, true, expectedHats);
        qj.quickJoinNoUserMasterDeploy("carol", user1);
    }

    function testQuickJoinNoUserMasterDeployByExecutor() public {
        vm.prank(address(mockExecutor));
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
        assertTrue(mockExecutor.hats().isWearerOfHat(user2, DEFAULT_HAT_ID));
    }

    function testQuickJoinWithUserMasterDeployEmitsEvent() public {
        registry.setUsername(user2, "bob");
        vm.prank(address(mockExecutor));
        vm.expectEmit(true, true, true, true);
        uint256[] memory expectedHats = new uint256[](1);
        expectedHats[0] = DEFAULT_HAT_ID;
        emit QuickJoinedByMaster(address(mockExecutor), user2, false, expectedHats);
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
}
