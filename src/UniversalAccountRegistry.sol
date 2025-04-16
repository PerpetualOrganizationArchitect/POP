// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/**
 * @title UniversalAccountRegistry
 * @dev A proxy-compatible contract for managing usernames across the POA protocol
 */
contract UniversalAccountRegistry is Initializable {
    // Protocol owner
    address public owner;

    // Mapping from address to username
    mapping(address => string) public addressToUsername;

    // Mapping to check if a username is already taken
    mapping(string => bool) private usernameExists;

    // Event for new registration
    event UserRegistered(address indexed accountAddress, string username);

    // Event for username change
    event UsernameChanged(address indexed accountAddress, string newUsername);

    // Event for ownership transfer
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Constructor is empty - use initialize instead
     */
    constructor() {}

    /**
     * @dev Initialize the contract with the initial owner
     */
    function initialize(address _owner) external initializer {
        require(_owner != address(0), "Invalid owner");
        owner = _owner;
    }

    /**
     * @dev Modifier to restrict function access to the owner
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
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

    // Function to register a new account with a unique username
    function registerAccount(string memory username) public {
        require(bytes(username).length > 0, "Username cannot be empty");
        require(bytes(addressToUsername[msg.sender]).length == 0, "Account already registered");
        require(!usernameExists[username], "Username already taken");

        addressToUsername[msg.sender] = username;
        usernameExists[username] = true;
        emit UserRegistered(msg.sender, username);
    }

    /**
     * @dev Register an account on behalf of another user (used by QuickJoin)
     */
    function registerAccountQuickJoin(string memory username, address newUser) public {
        require(bytes(username).length > 0, "Username cannot be empty");
        require(bytes(addressToUsername[newUser]).length == 0, "Account already registered");
        require(!usernameExists[username], "Username already taken");

        addressToUsername[newUser] = username;
        usernameExists[username] = true;
        emit UserRegistered(newUser, username);
    }

    // Function to change the username
    function changeUsername(string memory newUsername) public {
        string memory oldUsername = addressToUsername[msg.sender];
        require(bytes(oldUsername).length > 0, "Account not registered");
        require(bytes(newUsername).length > 0, "New username cannot be empty");
        require(!usernameExists[newUsername], "Username already taken");

        // Update the mappings
        usernameExists[oldUsername] = false;
        addressToUsername[msg.sender] = newUsername;
        usernameExists[newUsername] = true;

        emit UsernameChanged(msg.sender, newUsername);
    }

    // Function to get a username by address
    function getUsername(address accountAddress) public view returns (string memory) {
        return addressToUsername[accountAddress];
    }

    /**
     * @dev Version identifier to help with testing upgrades
     */
    function version() external pure returns (string memory) {
        return "v1";
    }
}
