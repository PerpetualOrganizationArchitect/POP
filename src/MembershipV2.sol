// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/**
 * @title MembershipV2
 * @dev An upgraded NFT-based membership contract with additional features
 */
contract MembershipV2 is ERC721, Initializable {
    // Token ID counter - simple uint counter instead of using library
    uint256 private _tokenIdCounter;
    
    // Organization owner
    address public owner;
    
    // Membership metadata
    string public orgName;
    
    // Track minted tokens
    mapping(uint256 => bool) private _minted;
    
    // Member metadata - tokenId => metadata
    mapping(uint256 => string) public memberMetadata;
    
    // Member roles - address => role
    mapping(address => string) public memberRoles;
    
    // Events
    event MemberAdded(address indexed member, uint256 tokenId);
    event MemberRemoved(address indexed member, uint256 tokenId);
    event MemberRoleSet(address indexed member, string role);
    event MemberMetadataSet(uint256 indexed tokenId, string metadata);
    
    /**
     * @dev Constructor is disabled - use initialize instead
     */
    constructor() ERC721("", "") {}
    
    /**
     * @dev Initialize the contract with org details
     */
    function initialize(address _owner, string memory _orgName) external initializer {
        require(_owner != address(0), "Invalid owner");
        
        owner = _owner;
        orgName = _orgName;
    }
    
    /**
     * @dev Modifier to restrict function access to the organization owner
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "Not org owner");
        _;
    }
    
    /**
     * @dev Check if a token exists (was minted and not burned)
     */
    function _exists(uint256 tokenId) internal view returns (bool) {
        return _minted[tokenId] && super._ownerOf(tokenId) != address(0);
    }
    
    /**
     * @dev Add a new member to the organization
     */
    function addMember(address member) external onlyOwner returns (uint256) {
        require(member != address(0), "Invalid member address");
        require(balanceOf(member) == 0, "Already a member");
        
        uint256 tokenId = _tokenIdCounter;
        _tokenIdCounter++;
        
        _safeMint(member, tokenId);
        _minted[tokenId] = true;
        
        emit MemberAdded(member, tokenId);
        
        return tokenId;
    }
    
    /**
     * @dev Add a new member with role to the organization
     */
    function addMemberWithRole(address member, string memory role) external onlyOwner returns (uint256) {
        uint256 tokenId = this.addMember(member);
        setMemberRole(member, role);
        return tokenId;
    }
    
    /**
     * @dev Remove a member from the organization
     */
    function removeMember(address member) external onlyOwner {
        require(balanceOf(member) > 0, "Not a member");
        
        // Find the token ID owned by this member
        uint256 tokenId;
        bool found = false;
        
        for (uint256 i = 0; i < _tokenIdCounter; i++) {
            if (_exists(i) && ownerOf(i) == member) {
                tokenId = i;
                found = true;
                break;
            }
        }
        
        require(found, "Membership token not found");
        
        // Clear the role
        memberRoles[member] = "";
        
        // Burn the token
        _burn(tokenId);
        
        emit MemberRemoved(member, tokenId);
    }
    
    /**
     * @dev Set metadata for a member token
     */
    function setMemberMetadata(uint256 tokenId, string memory metadata) external onlyOwner {
        require(_exists(tokenId), "Token does not exist");
        memberMetadata[tokenId] = metadata;
        emit MemberMetadataSet(tokenId, metadata);
    }
    
    /**
     * @dev Set a role for a member
     */
    function setMemberRole(address member, string memory role) public onlyOwner {
        require(balanceOf(member) > 0, "Not a member");
        memberRoles[member] = role;
        emit MemberRoleSet(member, role);
    }
    
    /**
     * @dev Check if an address is a member
     */
    function isMember(address account) external view returns (bool) {
        return balanceOf(account) > 0;
    }
    
    /**
     * @dev Check if a member has a specific role
     */
    function hasRole(address member, string memory role) external view returns (bool) {
        return balanceOf(member) > 0 && keccak256(bytes(memberRoles[member])) == keccak256(bytes(role));
    }
    
    /**
     * @dev Get a member's role
     */
    function getMemberRole(address member) external view returns (string memory) {
        require(balanceOf(member) > 0, "Not a member");
        return memberRoles[member];
    }
    
    /**
     * @dev Override name function to use orgName
     */
    function name() public view virtual override returns (string memory) {
        return bytes(orgName).length > 0 ? orgName : super.name();
    }
    
    /**
     * @dev Override the update method to prevent transfers between addresses
     * Only allow minting (from=0) and burning (to=0)
     */
    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address) {
        address from = super._ownerOf(tokenId);
        
        // Only allow minting and burning
        if (from != address(0) && to != address(0)) {
            revert("Membership cannot be transferred");
        }
        
        return super._update(to, tokenId, auth);
    }
    
    /**
     * @dev Version identifier to help with testing upgrades
     */
    function version() external pure returns (string memory) {
        return "v2";
    }
} 