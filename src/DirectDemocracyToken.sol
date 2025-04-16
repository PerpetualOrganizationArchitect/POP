// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

interface INFTMembership {
    function checkMemberTypeByAddress(address user) external view returns (string memory);
}

/**
 * @title DirectDemocracyToken
 * @dev A proxy-compatible global token contract for all orgs
 */
contract DirectDemocracyToken is Initializable, ERC20 {
    event Mint(address indexed to, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // Protocol owner
    address public owner;

    INFTMembership public nftMembership;

    uint256 public constant maxSupplyPerPerson = 100;

    address public quickJoin;
    bool public quickJoinSet = false;

    mapping(string => bool) private allowedRoles;

    // Token name and symbol stored in state variables
    string private _tokenName;
    string private _tokenSymbol;

    /**
     * @dev Constructor is empty - use initialize instead
     */
    constructor() ERC20("DirectDemocracyToken Proxy", "DDT") {}

    /**
     * @dev Override name function to use custom name
     */
    function name() public view virtual override returns (string memory) {
        return _tokenName;
    }
    
    /**
     * @dev Override symbol function to use custom symbol
     */
    function symbol() public view virtual override returns (string memory) {
        return _tokenSymbol;
    }

    /**
     * @dev Initialize the contract with initial settings
     */
    function initialize(
        address _owner,
        string memory name_,
        string memory symbol_,
        address _nftMembership,
        string[] memory _allowedRoleNames
    ) external initializer {
        require(_owner != address(0), "Invalid owner");
        require(_nftMembership != address(0), "Invalid NFT membership address");
        
        // Store token name and symbol for overriding getters
        _tokenName = name_;
        _tokenSymbol = symbol_;
        
        owner = _owner;
        nftMembership = INFTMembership(_nftMembership);

        for (uint256 i = 0; i < _allowedRoleNames.length; i++) {
            allowedRoles[_allowedRoleNames[i]] = true;
        }
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

    function setQuickJoin(address _quickJoin) public{
        require(!quickJoinSet, "QuickJoin already set");
        quickJoin = _quickJoin;
        quickJoinSet = true;
    }

    modifier onlyQuickJoin() {
        require(msg.sender == quickJoin, "Only QuickJoin can call this function");
        _;
    }

    modifier canMint(address newUser) {
        string memory memberType = nftMembership.checkMemberTypeByAddress(newUser);
        require(allowedRoles[memberType], "Not authorized to mint coins");
        _;
    }

    function decimals() public view virtual override returns (uint8) {
        return 0;
    }

    function mint(address newUser) public onlyQuickJoin {
        require(balanceOf(newUser) == 0, "This account has already claimed coins!");
        _mint(newUser, maxSupplyPerPerson);
        emit Mint(newUser, maxSupplyPerPerson);
    }

    function getBalance(address _address) public view returns (uint256) {
        return balanceOf(_address);
    }

    function transfer(address, /*to*/ uint256 /*amount*/ ) public virtual override returns (bool) {
        revert("Transfer of tokens is not allowed");
    }

    function approve(address, /*spender*/ uint256 /*amount*/ ) public virtual override returns (bool) {
        revert("Approval of Token allowance is not allowed");
    }

    function transferFrom(address, /*from*/ address, /*to*/ uint256 /*amount*/ )
        public
        virtual
        override
        returns (bool)
    {
        revert("Transfer of Tokens is not allowed");
    }
    
    /**
     * @dev Version identifier to help with testing upgrades
     */
    function version() external pure returns (string memory) {
        return "v1";
    }
}
