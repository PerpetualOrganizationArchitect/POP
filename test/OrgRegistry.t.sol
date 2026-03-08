// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/OrgRegistry.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @dev Mock Hats contract for testing
contract MockHats {
    mapping(address => mapping(uint256 => bool)) public wearers;

    function setWearer(address account, uint256 hatId, bool isWearer) external {
        wearers[account][hatId] = isWearer;
    }

    function isWearerOfHat(address account, uint256 hatId) external view returns (bool) {
        return wearers[account][hatId];
    }
}

contract OrgRegistryTest is Test {
    OrgRegistry reg;
    MockHats mockHats;
    bytes32 ORG_ID = keccak256("ORG");
    uint256 constant TOP_HAT_ID = 1;
    uint256 constant ADMIN_HAT_ID = 2;
    address constant ADMIN_USER = address(0xAD);
    address constant NON_ADMIN_USER = address(0xBA);

    function setUp() public {
        // Deploy mock hats
        mockHats = new MockHats();

        // Deploy OrgRegistry with mock hats
        OrgRegistry impl = new OrgRegistry();
        bytes memory data = abi.encodeCall(OrgRegistry.initialize, (address(this), address(mockHats)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), data);
        reg = OrgRegistry(address(proxy));
    }

    function testRegisterOrgAndContract() public {
        reg.registerOrg(ORG_ID, address(this), bytes("Test Org"), bytes32(0));
        bytes32 typeId = keccak256("TYPE");
        reg.registerOrgContract(ORG_ID, typeId, address(0x1), address(0x2), true, address(this), true);
        (address executor,,,) = reg.orgOf(ORG_ID);
        assertEq(executor, address(this));
        address proxy = reg.proxyOf(ORG_ID, typeId);
        assertEq(proxy, address(0x1));
    }

    function testGetHats() public view {
        assertEq(reg.getHats(), address(mockHats));
    }

    /* ══════════ Metadata Admin Tests ══════════ */

    function testUpdateOrgMetaAsAdmin_WithTopHat() public {
        // Setup: register org and hats tree
        reg.registerOrg(ORG_ID, address(this), bytes("Test Org"), bytes32(0));
        uint256[] memory roleHats = new uint256[](0);
        reg.registerHatsTree(ORG_ID, TOP_HAT_ID, roleHats);

        // Make ADMIN_USER wear the top hat
        mockHats.setWearer(ADMIN_USER, TOP_HAT_ID, true);

        // Should succeed when caller wears top hat
        vm.prank(ADMIN_USER);
        reg.updateOrgMetaAsAdmin(ORG_ID, bytes("New Name"), bytes32(uint256(1)));

        // Verify event was emitted (implicitly tested by no revert)
    }

    function testUpdateOrgMetaAsAdmin_WithCustomAdminHat() public {
        // Setup: register org and hats tree
        reg.registerOrg(ORG_ID, address(this), bytes("Test Org"), bytes32(0));
        uint256[] memory roleHats = new uint256[](0);
        reg.registerHatsTree(ORG_ID, TOP_HAT_ID, roleHats);

        // Set custom metadata admin hat (as executor)
        reg.setOrgMetadataAdminHat(ORG_ID, ADMIN_HAT_ID);

        // Make ADMIN_USER wear the custom admin hat (not the top hat)
        mockHats.setWearer(ADMIN_USER, ADMIN_HAT_ID, true);

        // Should succeed when caller wears custom admin hat
        vm.prank(ADMIN_USER);
        reg.updateOrgMetaAsAdmin(ORG_ID, bytes("New Name"), bytes32(uint256(1)));
    }

    function testUpdateOrgMetaAsAdmin_RevertWhenNotWearingHat() public {
        // Setup: register org and hats tree
        reg.registerOrg(ORG_ID, address(this), bytes("Test Org"), bytes32(0));
        uint256[] memory roleHats = new uint256[](0);
        reg.registerHatsTree(ORG_ID, TOP_HAT_ID, roleHats);

        // NON_ADMIN_USER doesn't wear any hat
        vm.prank(NON_ADMIN_USER);
        vm.expectRevert(NotOrgMetadataAdmin.selector);
        reg.updateOrgMetaAsAdmin(ORG_ID, bytes("New Name"), bytes32(uint256(1)));
    }

    function testUpdateOrgMetaAsAdmin_RevertWhenNoHatsConfigured() public {
        // Setup: register org but NO hats tree
        reg.registerOrg(ORG_ID, address(this), bytes("Test Org"), bytes32(0));

        // Should revert because no top hat or admin hat is set
        vm.prank(ADMIN_USER);
        vm.expectRevert(NotOrgMetadataAdmin.selector);
        reg.updateOrgMetaAsAdmin(ORG_ID, bytes("New Name"), bytes32(uint256(1)));
    }

    function testUpdateOrgMetaAsAdmin_RevertWhenOrgUnknown() public {
        bytes32 unknownOrgId = keccak256("UNKNOWN");

        vm.prank(ADMIN_USER);
        vm.expectRevert(OrgUnknown.selector);
        reg.updateOrgMetaAsAdmin(unknownOrgId, bytes("New Name"), bytes32(uint256(1)));
    }

    function testSetOrgMetadataAdminHat_Success() public {
        // Setup: register org
        reg.registerOrg(ORG_ID, address(this), bytes("Test Org"), bytes32(0));

        // Set metadata admin hat (as executor - which is address(this))
        reg.setOrgMetadataAdminHat(ORG_ID, ADMIN_HAT_ID);

        // Verify it was set
        assertEq(reg.getOrgMetadataAdminHat(ORG_ID), ADMIN_HAT_ID);
    }

    function testSetOrgMetadataAdminHat_RevertWhenNotExecutor() public {
        // Setup: register org with address(this) as executor
        reg.registerOrg(ORG_ID, address(this), bytes("Test Org"), bytes32(0));

        // Try to set from non-executor
        vm.prank(NON_ADMIN_USER);
        vm.expectRevert(NotOrgExecutor.selector);
        reg.setOrgMetadataAdminHat(ORG_ID, ADMIN_HAT_ID);
    }

    function testSetOrgMetadataAdminHat_CanResetToZero() public {
        // Setup: register org and set admin hat
        reg.registerOrg(ORG_ID, address(this), bytes("Test Org"), bytes32(0));
        reg.setOrgMetadataAdminHat(ORG_ID, ADMIN_HAT_ID);

        // Reset to zero (falls back to topHat)
        reg.setOrgMetadataAdminHat(ORG_ID, 0);

        assertEq(reg.getOrgMetadataAdminHat(ORG_ID), 0);
    }

    function testGetOrgMetadataAdminHat_ReturnsZeroByDefault() public {
        // Setup: register org
        reg.registerOrg(ORG_ID, address(this), bytes("Test Org"), bytes32(0));

        // Should return 0 if not set
        assertEq(reg.getOrgMetadataAdminHat(ORG_ID), 0);
    }

    function testUpdateOrgMetaAsAdmin_CustomHatTakesPrecedenceOverTopHat() public {
        // Setup: register org and hats tree
        reg.registerOrg(ORG_ID, address(this), bytes("Test Org"), bytes32(0));
        uint256[] memory roleHats = new uint256[](0);
        reg.registerHatsTree(ORG_ID, TOP_HAT_ID, roleHats);

        // Set custom metadata admin hat
        reg.setOrgMetadataAdminHat(ORG_ID, ADMIN_HAT_ID);

        // ADMIN_USER wears top hat but NOT custom admin hat
        mockHats.setWearer(ADMIN_USER, TOP_HAT_ID, true);
        mockHats.setWearer(ADMIN_USER, ADMIN_HAT_ID, false);

        // Should FAIL because custom admin hat takes precedence
        vm.prank(ADMIN_USER);
        vm.expectRevert(NotOrgMetadataAdmin.selector);
        reg.updateOrgMetaAsAdmin(ORG_ID, bytes("New Name"), bytes32(uint256(1)));
    }

    /* ══════════ Org Name Uniqueness on Update ══════════ */

    function testUpdateOrgMeta_RevertWhenNameTaken() public {
        // Register two orgs with different names
        bytes32 orgA = keccak256("ORG_A");
        bytes32 orgB = keccak256("ORG_B");
        reg.registerOrg(orgA, address(this), bytes("Alpha"), bytes32(0));
        reg.registerOrg(orgB, address(this), bytes("Beta"), bytes32(0));

        // Try to rename Alpha to Beta via executor path — should fail
        vm.expectRevert(OrgNameTaken.selector);
        reg.updateOrgMeta(orgA, bytes("Beta"), bytes32(0));
    }

    function testUpdateOrgMeta_SameNameNoOp() public {
        bytes32 orgA = keccak256("ORG_A");
        reg.registerOrg(orgA, address(this), bytes("Alpha"), bytes32(0));

        // Updating to the same name should succeed (no-op)
        reg.updateOrgMeta(orgA, bytes("Alpha"), bytes32(uint256(1)));
    }

    function testUpdateOrgMeta_ReleasesOldName() public {
        bytes32 orgA = keccak256("ORG_A");
        bytes32 orgB = keccak256("ORG_B");
        reg.registerOrg(orgA, address(this), bytes("Alpha"), bytes32(0));

        // Rename Alpha → Gamma
        reg.updateOrgMeta(orgA, bytes("Gamma"), bytes32(0));

        // "Alpha" is now free — a new org should be able to claim it
        reg.registerOrg(orgB, address(this), bytes("Alpha"), bytes32(0));
        assertTrue(reg.isOrgNameTaken(bytes("Alpha")));
    }

    function testUpdateOrgMeta_CaseInsensitive() public {
        bytes32 orgA = keccak256("ORG_A");
        bytes32 orgB = keccak256("ORG_B");
        reg.registerOrg(orgA, address(this), bytes("Alpha"), bytes32(0));
        reg.registerOrg(orgB, address(this), bytes("Beta"), bytes32(0));

        // "BETA" should collide with "Beta" (case-insensitive)
        vm.expectRevert(OrgNameTaken.selector);
        reg.updateOrgMeta(orgA, bytes("BETA"), bytes32(0));
    }

    function testUpdateOrgMetaAsAdmin_RevertWhenNameTaken() public {
        bytes32 orgA = keccak256("ORG_A");
        bytes32 orgB = keccak256("ORG_B");
        reg.registerOrg(orgA, address(this), bytes("Alpha"), bytes32(0));
        reg.registerOrg(orgB, address(this), bytes("Beta"), bytes32(0));

        // Setup hats for admin path
        uint256[] memory roleHats = new uint256[](0);
        reg.registerHatsTree(orgA, TOP_HAT_ID, roleHats);
        mockHats.setWearer(ADMIN_USER, TOP_HAT_ID, true);

        // Admin tries to rename Alpha to Beta — should fail
        vm.prank(ADMIN_USER);
        vm.expectRevert(OrgNameTaken.selector);
        reg.updateOrgMetaAsAdmin(orgA, bytes("Beta"), bytes32(0));
    }

    function testUpdateOrgMeta_EmptyNameSkipsUniqueness() public {
        bytes32 orgA = keccak256("ORG_A");
        reg.registerOrg(orgA, address(this), bytes("Alpha"), bytes32(0));

        // Empty name = metadata-only update, should not touch name mappings
        reg.updateOrgMeta(orgA, bytes(""), bytes32(uint256(42)));

        // Name still registered
        assertTrue(reg.isOrgNameTaken(bytes("Alpha")));
        assertEq(reg.orgIdOfName(bytes("Alpha")), orgA);
    }
}
