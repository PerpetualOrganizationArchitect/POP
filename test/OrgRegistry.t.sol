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
}
