// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/OrgRegistry.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract OrgRegistryTest is Test {
    OrgRegistry reg;
    bytes32 ORG_ID = keccak256("ORG");

    function setUp() public {
        OrgRegistry impl = new OrgRegistry();
        bytes memory data = abi.encodeCall(OrgRegistry.initialize, (address(this)));
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
}
