// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

interface IMembershipNFT {
    function mintDefaultNFT(address newUser) external;
}

interface IDirectDemocracyToken {
    function mint(address newUser) external;
}

// interface for UniversalAccountRegistry.sol
interface IUniversalAccountRegistry {
    function getUsername(address accountAddress) external view returns (string memory);
    function registerAccount(string memory username) external;
    function registerAccountQuickJoin(string memory username, address newUser) external;
}

/**
 * @title QuickJoin
 * @dev A proxy-compatible contract for onboarding users quickly
 */
contract QuickJoin is Initializable {
    IMembershipNFT private membershipNFT;
    IDirectDemocracyToken private directDemocracyToken;
    IUniversalAccountRegistry private accountRegistry;

    address public owner;
    address public masterDeployAddress;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Constructor is empty - use initialize instead
     */
    constructor() {}

    /**
     * @dev Initialize the contract with required addresses
     */
    function initialize(
        address _owner,
        address _membershipNFTAddress,
        address _directDemocracyTokenAddress,
        address _accountRegistryAddress,
        address _masterDeployAddress
    ) external initializer {
        require(_owner != address(0), "Invalid owner");
        require(_membershipNFTAddress != address(0), "Invalid membership NFT address");
        require(_directDemocracyTokenAddress != address(0), "Invalid token address");
        require(_accountRegistryAddress != address(0), "Invalid account registry address");
        require(_masterDeployAddress != address(0), "Invalid master deploy address");
        
        owner = _owner;
        membershipNFT = IMembershipNFT(_membershipNFTAddress);
        directDemocracyToken = IDirectDemocracyToken(_directDemocracyTokenAddress);
        accountRegistry = IUniversalAccountRegistry(_accountRegistryAddress);
        masterDeployAddress = _masterDeployAddress;
    }

    /**
     * @dev Modifier to restrict function access to the owner
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    modifier onlyMasterDeploy() {
        require(msg.sender == masterDeployAddress, "Only MasterDeploy can call this function");
        _;
    }

    /**
     * @dev Transfer ownership of the contract to a new account
     */
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "New owner is the zero address");
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    /**
     * @dev Update contract addresses
     */
    function updateAddresses(
        address _membershipNFTAddress,
        address _directDemocracyTokenAddress,
        address _accountRegistryAddress,
        address _masterDeployAddress
    ) external onlyOwner {
        require(_membershipNFTAddress != address(0), "Invalid membership NFT address");
        require(_directDemocracyTokenAddress != address(0), "Invalid token address");
        require(_accountRegistryAddress != address(0), "Invalid account registry address");
        require(_masterDeployAddress != address(0), "Invalid master deploy address");
        
        membershipNFT = IMembershipNFT(_membershipNFTAddress);
        directDemocracyToken = IDirectDemocracyToken(_directDemocracyTokenAddress);
        accountRegistry = IUniversalAccountRegistry(_accountRegistryAddress);
        masterDeployAddress = _masterDeployAddress;
    }

    function quickJoinNoUser(string memory userName) public {
        string memory existingUsername = accountRegistry.getUsername(msg.sender);

        // Check if the user has an existing username
        if (bytes(existingUsername).length == 0) {
            accountRegistry.registerAccountQuickJoin(userName, msg.sender);
        }
        membershipNFT.mintDefaultNFT(msg.sender);
        directDemocracyToken.mint(msg.sender);
    }

    function quickJoinWithUser() public {
        membershipNFT.mintDefaultNFT(msg.sender);
        directDemocracyToken.mint(msg.sender);
    }

    function quickJoinNoUserMasterDeploy(string memory userName, address newUser) public onlyMasterDeploy {
        string memory existingUsername = accountRegistry.getUsername(newUser);

        // Check if the user has an existing username
        if (bytes(existingUsername).length == 0) {
            accountRegistry.registerAccountQuickJoin(userName, newUser);
        }
        membershipNFT.mintDefaultNFT(newUser);
        directDemocracyToken.mint(newUser);
    }

    function quickJoinWithUserMasterDeploy(address newUser) public onlyMasterDeploy {
        membershipNFT.mintDefaultNFT(newUser);
        directDemocracyToken.mint(newUser);
    }
    
    /**
     * @dev Version identifier to help with testing upgrades
     */
    function version() external pure returns (string memory) {
        return "v1";
    }
}
