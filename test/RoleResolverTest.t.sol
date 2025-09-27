// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {RoleResolver} from "../src/libs/RoleResolver.sol";
import {OrgRegistry} from "../src/OrgRegistry.sol";

// Test harness to expose RoleResolver library functions
contract RoleResolverHarness {
    using RoleResolver for *;
    
    function resolveRoleHats(
        OrgRegistry orgRegistry,
        bytes32 orgId,
        uint256[] memory roleIndices
    ) external view returns (uint256[] memory) {
        return RoleResolver.resolveRoleHats(orgRegistry, orgId, roleIndices);
    }
}

// Mock OrgRegistry for testing
contract MockOrgRegistry {
    mapping(bytes32 => uint256[]) private roleHats;
    
    function registerHatsTree(bytes32 orgId, uint256 topHatId, uint256[] memory roleHatIds) external {
        roleHats[orgId] = roleHatIds;
    }
    
    function getRoleHat(bytes32 orgId, uint256 roleIndex) external view returns (uint256) {
        uint256[] memory hats = roleHats[orgId];
        if (roleIndex >= hats.length) return 0;
        return hats[roleIndex];
    }
}

contract RoleResolverTest is Test {
    RoleResolverHarness resolver;
    MockOrgRegistry orgRegistry;
    
    bytes32 constant ORG_ID = keccak256("TEST-ORG");
    uint256 constant TOP_HAT = 1000;
    
    function setUp() public {
        resolver = new RoleResolverHarness();
        orgRegistry = new MockOrgRegistry();
        
        // Setup a mock org with role hats
        uint256[] memory roleHatIds = new uint256[](3);
        roleHatIds[0] = 1001; // DEFAULT
        roleHatIds[1] = 1002; // EXECUTIVE
        roleHatIds[2] = 1003; // ADMIN
        
        orgRegistry.registerHatsTree(ORG_ID, TOP_HAT, roleHatIds);
    }
    
    function testResolveEmptyRoles() public {
        uint256[] memory empty = new uint256[](0);
        uint256[] memory result = resolver.resolveRoleHats(OrgRegistry(address(orgRegistry)), ORG_ID, empty);
        assertEq(result.length, 0);
    }
    
    function testResolveSingleRole() public {
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0; // DEFAULT role
        
        uint256[] memory result = resolver.resolveRoleHats(OrgRegistry(address(orgRegistry)), ORG_ID, indices);
        assertEq(result.length, 1);
        assertEq(result[0], 1001);
    }
    
    function testResolveMultipleRoles() public {
        uint256[] memory indices = new uint256[](3);
        indices[0] = 0; // DEFAULT
        indices[1] = 1; // EXECUTIVE
        indices[2] = 2; // ADMIN
        
        uint256[] memory result = resolver.resolveRoleHats(OrgRegistry(address(orgRegistry)), ORG_ID, indices);
        assertEq(result.length, 3);
        assertEq(result[0], 1001);
        assertEq(result[1], 1002);
        assertEq(result[2], 1003);
    }
    
    function testResolveDuplicateRoles() public {
        uint256[] memory indices = new uint256[](4);
        indices[0] = 0; // DEFAULT
        indices[1] = 1; // EXECUTIVE
        indices[2] = 0; // DEFAULT again
        indices[3] = 1; // EXECUTIVE again
        
        uint256[] memory result = resolver.resolveRoleHats(OrgRegistry(address(orgRegistry)), ORG_ID, indices);
        assertEq(result.length, 4);
        assertEq(result[0], 1001);
        assertEq(result[1], 1002);
        assertEq(result[2], 1001); // Duplicate
        assertEq(result[3], 1002); // Duplicate
    }
    
    function testResolveOutOfBoundsIndex() public {
        uint256[] memory indices = new uint256[](2);
        indices[0] = 0; // Valid
        indices[1] = 10; // Out of bounds - should return 0
        
        uint256[] memory result = resolver.resolveRoleHats(OrgRegistry(address(orgRegistry)), ORG_ID, indices);
        assertEq(result.length, 2);
        assertEq(result[0], 1001);
        assertEq(result[1], 0); // Out of bounds returns 0
    }
    
    function testResolveNonExistentOrg() public {
        bytes32 fakeOrgId = keccak256("FAKE-ORG");
        uint256[] memory indices = new uint256[](1);
        indices[0] = 0;
        
        uint256[] memory result = resolver.resolveRoleHats(OrgRegistry(address(orgRegistry)), fakeOrgId, indices);
        assertEq(result.length, 1);
        assertEq(result[0], 0); // Non-existent org returns 0
    }
    
    function testResolveReverseOrder() public {
        uint256[] memory indices = new uint256[](3);
        indices[0] = 2; // ADMIN
        indices[1] = 1; // EXECUTIVE
        indices[2] = 0; // DEFAULT
        
        uint256[] memory result = resolver.resolveRoleHats(OrgRegistry(address(orgRegistry)), ORG_ID, indices);
        assertEq(result.length, 3);
        assertEq(result[0], 1003);
        assertEq(result[1], 1002);
        assertEq(result[2], 1001);
    }
    
    function testGasEfficiencyWithManyRoles() public {
        // Test with a large array to ensure gas efficiency
        uint256[] memory indices = new uint256[](20);
        for (uint256 i = 0; i < 20; i++) {
            indices[i] = i % 3; // Cycle through 0, 1, 2
        }
        
        uint256 gasBefore = gasleft();
        uint256[] memory result = resolver.resolveRoleHats(OrgRegistry(address(orgRegistry)), ORG_ID, indices);
        uint256 gasUsed = gasBefore - gasleft();
        
        console.log("Gas used for resolving 20 roles:", gasUsed);
        assertEq(result.length, 20);
        
        // Verify pattern
        for (uint256 i = 0; i < 20; i++) {
            uint256 expectedHat = 1001 + (i % 3);
            if (i % 3 < 3) { // Within bounds
                assertEq(result[i], expectedHat);
            }
        }
    }
}