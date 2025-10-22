// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/DeviceWrapRegistry.sol";
import "../src/UniversalAccountRegistry.sol";
import "../test/mocks/MockHats.sol";

contract DeviceWrapRegistryTest is Test {
    DeviceWrapRegistry public registry;
    UniversalAccountRegistry public uar;
    MockHats public hats;

    address public poaManager = address(0x1);
    address public guardian1 = address(0x2);
    address public guardian2 = address(0x3);
    address public guardian3 = address(0x4);
    address public user1 = address(0x5);
    address public user2 = address(0x6);

    uint256 public constant GUARDIAN_HAT_ID = 100;

    function setUp() public {
        // Deploy contracts
        hats = new MockHats();
        uar = new UniversalAccountRegistry();
        registry = new DeviceWrapRegistry();

        // Initialize UAR
        uar.initialize(poaManager);

        // Initialize DeviceWrapRegistry
        vm.prank(poaManager);
        registry.initialize(poaManager, address(uar), address(hats));

        // Setup guardian hat
        vm.prank(poaManager);
        registry.setGuardianHat(GUARDIAN_HAT_ID);

        // Mint guardian hats to guardians
        hats.mintHat(GUARDIAN_HAT_ID, guardian1);
        hats.mintHat(GUARDIAN_HAT_ID, guardian2);
        hats.mintHat(GUARDIAN_HAT_ID, guardian3);

        // Set recovery caller in UAR
        vm.prank(poaManager);
        uar.setRecoveryCaller(address(registry));

        // Register users in UAR
        vm.prank(user1);
        uar.registerAccount("alice");

        vm.prank(user2);
        uar.registerAccount("bob");
    }

    function testInitialization() public {
        assertEq(registry.maxInstantWraps(), 3, "Default max instant wraps should be 3");
        assertEq(registry.guardianThreshold(), 1, "Default guardian threshold should be 1");
        assertEq(registry.guardianHatId(), GUARDIAN_HAT_ID, "Guardian hat ID should be set");
    }

    function testIsGuardian() public {
        assertTrue(registry.isGuardian(guardian1), "Guardian1 should be guardian");
        assertTrue(registry.isGuardian(guardian2), "Guardian2 should be guardian");
        assertTrue(registry.isGuardian(guardian3), "Guardian3 should be guardian");
        assertFalse(registry.isGuardian(user1), "User1 should not be guardian");
    }

    function testAddWrapWithinCap() public {
        DeviceWrapRegistry.Wrap memory wrap = DeviceWrapRegistry.Wrap({
            credentialHint: bytes32(uint256(1)),
            salt: bytes32(uint256(2)),
            iv: bytes12(uint96(3)),
            aadHash: bytes32(uint256(4)),
            cid: "ipfs://test",
            status: DeviceWrapRegistry.WrapStatus.Active,
            createdAt: 0
        });

        vm.prank(user1);
        uint256 idx = registry.addWrap(wrap);

        assertEq(idx, 0, "First wrap index should be 0");
        assertEq(registry.activeCount(user1), 1, "Active count should be 1");

        DeviceWrapRegistry.Wrap[] memory wraps = registry.wrapsOf(user1);
        assertEq(wraps.length, 1, "Should have 1 wrap");
        assertEq(uint8(wraps[0].status), uint8(DeviceWrapRegistry.WrapStatus.Active), "Wrap should be Active");
    }

    function testAddWrapOverCapRequiresApproval() public {
        // Add 3 wraps (up to cap)
        for (uint256 i = 0; i < 3; i++) {
            DeviceWrapRegistry.Wrap memory wrap = DeviceWrapRegistry.Wrap({
                credentialHint: bytes32(i + 1),
                salt: bytes32(i + 2),
                iv: bytes12(uint96(i + 3)),
                aadHash: bytes32(i + 4),
                cid: string(abi.encodePacked("ipfs://test", i)),
                status: DeviceWrapRegistry.WrapStatus.Active,
                createdAt: 0
            });

            vm.prank(user1);
            registry.addWrap(wrap);
        }

        assertEq(registry.activeCount(user1), 3, "Should have 3 active wraps");

        // Add 4th wrap (over cap)
        DeviceWrapRegistry.Wrap memory wrap4 = DeviceWrapRegistry.Wrap({
            credentialHint: bytes32(uint256(10)),
            salt: bytes32(uint256(11)),
            iv: bytes12(uint96(12)),
            aadHash: bytes32(uint256(13)),
            cid: "ipfs://test4",
            status: DeviceWrapRegistry.WrapStatus.Active,
            createdAt: 0
        });

        vm.prank(user1);
        uint256 idx = registry.addWrap(wrap4);

        DeviceWrapRegistry.Wrap[] memory wraps = registry.wrapsOf(user1);
        assertEq(uint8(wraps[idx].status), uint8(DeviceWrapRegistry.WrapStatus.Pending), "4th wrap should be Pending");
        assertEq(registry.activeCount(user1), 3, "Should still have 3 active wraps");
    }

    function testGuardianApproveWrap() public {
        // Add 3 wraps to reach cap
        for (uint256 i = 0; i < 3; i++) {
            DeviceWrapRegistry.Wrap memory wrap = DeviceWrapRegistry.Wrap({
                credentialHint: bytes32(i + 1),
                salt: bytes32(i + 2),
                iv: bytes12(uint96(i + 3)),
                aadHash: bytes32(i + 4),
                cid: string(abi.encodePacked("ipfs://test", i)),
                status: DeviceWrapRegistry.WrapStatus.Active,
                createdAt: 0
            });

            vm.prank(user1);
            registry.addWrap(wrap);
        }

        // Add pending wrap
        DeviceWrapRegistry.Wrap memory wrap4 = DeviceWrapRegistry.Wrap({
            credentialHint: bytes32(uint256(10)),
            salt: bytes32(uint256(11)),
            iv: bytes12(uint96(12)),
            aadHash: bytes32(uint256(13)),
            cid: "ipfs://test4",
            status: DeviceWrapRegistry.WrapStatus.Active,
            createdAt: 0
        });

        vm.prank(user1);
        uint256 idx = registry.addWrap(wrap4);

        // Guardian approves
        vm.prank(guardian1);
        registry.guardianApproveWrap(user1, idx);

        // Should auto-finalize with threshold of 1
        DeviceWrapRegistry.Wrap[] memory wraps = registry.wrapsOf(user1);
        assertEq(uint8(wraps[idx].status), uint8(DeviceWrapRegistry.WrapStatus.Active), "Wrap should be Active");
        assertEq(registry.activeCount(user1), 4, "Should have 4 active wraps");
    }

    function testGuardianApproveWrapWithThreshold() public {
        // Set threshold to 2
        vm.prank(poaManager);
        registry.setGuardianThreshold(2);

        // Add 3 wraps to reach cap
        for (uint256 i = 0; i < 3; i++) {
            DeviceWrapRegistry.Wrap memory wrap = DeviceWrapRegistry.Wrap({
                credentialHint: bytes32(i + 1),
                salt: bytes32(i + 2),
                iv: bytes12(uint96(i + 3)),
                aadHash: bytes32(i + 4),
                cid: string(abi.encodePacked("ipfs://test", i)),
                status: DeviceWrapRegistry.WrapStatus.Active,
                createdAt: 0
            });

            vm.prank(user1);
            registry.addWrap(wrap);
        }

        // Add pending wrap
        DeviceWrapRegistry.Wrap memory wrap4 = DeviceWrapRegistry.Wrap({
            credentialHint: bytes32(uint256(10)),
            salt: bytes32(uint256(11)),
            iv: bytes12(uint96(12)),
            aadHash: bytes32(uint256(13)),
            cid: "ipfs://test4",
            status: DeviceWrapRegistry.WrapStatus.Active,
            createdAt: 0
        });

        vm.prank(user1);
        uint256 idx = registry.addWrap(wrap4);

        // First guardian approves
        vm.prank(guardian1);
        registry.guardianApproveWrap(user1, idx);

        DeviceWrapRegistry.Wrap[] memory wraps = registry.wrapsOf(user1);
        assertEq(uint8(wraps[idx].status), uint8(DeviceWrapRegistry.WrapStatus.Pending), "Wrap should still be Pending");

        // Second guardian approves - should finalize
        vm.prank(guardian2);
        registry.guardianApproveWrap(user1, idx);

        wraps = registry.wrapsOf(user1);
        assertEq(uint8(wraps[idx].status), uint8(DeviceWrapRegistry.WrapStatus.Active), "Wrap should be Active");
        assertEq(registry.activeCount(user1), 4, "Should have 4 active wraps");
    }

    function testRevokeWrap() public {
        DeviceWrapRegistry.Wrap memory wrap = DeviceWrapRegistry.Wrap({
            credentialHint: bytes32(uint256(1)),
            salt: bytes32(uint256(2)),
            iv: bytes12(uint96(3)),
            aadHash: bytes32(uint256(4)),
            cid: "ipfs://test",
            status: DeviceWrapRegistry.WrapStatus.Active,
            createdAt: 0
        });

        vm.prank(user1);
        uint256 idx = registry.addWrap(wrap);

        vm.prank(user1);
        registry.revokeWrap(idx);

        DeviceWrapRegistry.Wrap[] memory wraps = registry.wrapsOf(user1);
        assertEq(uint8(wraps[idx].status), uint8(DeviceWrapRegistry.WrapStatus.Revoked), "Wrap should be Revoked");
        assertEq(registry.activeCount(user1), 0, "Should have 0 active wraps");
    }

    function testProposeAccountTransfer() public {
        vm.prank(user1);
        registry.proposeAccountTransfer(user1, user2);

        (,, bool executed, uint64 createdAt, uint32 approvals) = registry.getTransferState(user1, user2);
        assertFalse(executed, "Transfer should not be executed");
        assertGt(createdAt, 0, "CreatedAt should be set");
        assertEq(approvals, 0, "Should have 0 approvals");
    }

    function testGuardianApproveTransfer() public {
        vm.prank(user1);
        registry.proposeAccountTransfer(user1, address(0x999));

        // Guardian approves
        vm.prank(guardian1);
        registry.guardianApproveTransfer(user1, address(0x999));

        // Should auto-execute with threshold of 1
        (,, bool executed,,) = registry.getTransferState(user1, address(0x999));
        assertTrue(executed, "Transfer should be executed");

        // Verify username was transferred in UAR
        assertEq(uar.getUsername(address(0x999)), "alice", "Username should be transferred");
        assertEq(uar.getUsername(user1), "", "Old address should have no username");
    }

    function testGuardianApproveTransferWithThreshold() public {
        // Set threshold to 2
        vm.prank(poaManager);
        registry.setGuardianThreshold(2);

        vm.prank(user1);
        registry.proposeAccountTransfer(user1, address(0x999));

        // First guardian approves
        vm.prank(guardian1);
        registry.guardianApproveTransfer(user1, address(0x999));

        (,, bool executed,, uint32 approvals) = registry.getTransferState(user1, address(0x999));
        assertFalse(executed, "Transfer should not be executed yet");
        assertEq(approvals, 1, "Should have 1 approval");

        // Second guardian approves - should execute
        vm.prank(guardian2);
        registry.guardianApproveTransfer(user1, address(0x999));

        (,, executed,,) = registry.getTransferState(user1, address(0x999));
        assertTrue(executed, "Transfer should be executed");

        // Verify username was transferred
        assertEq(uar.getUsername(address(0x999)), "alice", "Username should be transferred");
    }

    function testCannotApproveWrapTwice() public {
        // Add 3 wraps to reach cap
        for (uint256 i = 0; i < 3; i++) {
            DeviceWrapRegistry.Wrap memory wrap = DeviceWrapRegistry.Wrap({
                credentialHint: bytes32(i + 1),
                salt: bytes32(i + 2),
                iv: bytes12(uint96(i + 3)),
                aadHash: bytes32(i + 4),
                cid: string(abi.encodePacked("ipfs://test", i)),
                status: DeviceWrapRegistry.WrapStatus.Active,
                createdAt: 0
            });

            vm.prank(user1);
            registry.addWrap(wrap);
        }

        // Set threshold to 2
        vm.prank(poaManager);
        registry.setGuardianThreshold(2);

        // Add pending wrap
        DeviceWrapRegistry.Wrap memory wrap4 = DeviceWrapRegistry.Wrap({
            credentialHint: bytes32(uint256(10)),
            salt: bytes32(uint256(11)),
            iv: bytes12(uint96(12)),
            aadHash: bytes32(uint256(13)),
            cid: "ipfs://test4",
            status: DeviceWrapRegistry.WrapStatus.Active,
            createdAt: 0
        });

        vm.prank(user1);
        uint256 idx = registry.addWrap(wrap4);

        // Guardian approves once
        vm.prank(guardian1);
        registry.guardianApproveWrap(user1, idx);

        // Guardian tries to approve again - should revert
        vm.prank(guardian1);
        vm.expectRevert(DeviceWrapRegistry.AlreadyVoted.selector);
        registry.guardianApproveWrap(user1, idx);
    }

    function testNonGuardianCannotApprove() public {
        // Add 3 wraps to reach cap
        for (uint256 i = 0; i < 3; i++) {
            DeviceWrapRegistry.Wrap memory wrap = DeviceWrapRegistry.Wrap({
                credentialHint: bytes32(i + 1),
                salt: bytes32(i + 2),
                iv: bytes12(uint96(i + 3)),
                aadHash: bytes32(i + 4),
                cid: string(abi.encodePacked("ipfs://test", i)),
                status: DeviceWrapRegistry.WrapStatus.Active,
                createdAt: 0
            });

            vm.prank(user1);
            registry.addWrap(wrap);
        }

        // Add pending wrap
        DeviceWrapRegistry.Wrap memory wrap4 = DeviceWrapRegistry.Wrap({
            credentialHint: bytes32(uint256(10)),
            salt: bytes32(uint256(11)),
            iv: bytes12(uint96(12)),
            aadHash: bytes32(uint256(13)),
            cid: "ipfs://test4",
            status: DeviceWrapRegistry.WrapStatus.Active,
            createdAt: 0
        });

        vm.prank(user1);
        uint256 idx = registry.addWrap(wrap4);

        // Non-guardian tries to approve - should revert
        vm.prank(user2);
        vm.expectRevert(DeviceWrapRegistry.NotGuardian.selector);
        registry.guardianApproveWrap(user1, idx);
    }
}
