// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

/**
 * @title NFTMembership
 * @dev A proxy-compatible NFT membership contract with advanced features
 */

contract NFTMembership is ERC721URIStorage, Initializable {
    uint256 private _nextTokenId;

    // Organization owner
    address public owner;
    
    // Token metadata that overrides the constructor values
    string private _tokenName;
    string private _tokenSymbol;

    mapping(uint256 => string) public memberTypeNames;
    mapping(string => string) public memberTypeImages;
    mapping(address => string) public memberTypeOf;
    mapping(uint256 => string) public executiveRoleNames;
    mapping(string => bool) public isExecutiveRole;
    mapping(address => uint256) public lastDowngradeTime;

    address public quickJoin;
    bool public quickJoinSet = false;

    address public electionContract;
    uint256 private constant ONE_WEEK = 1 weeks;

    string private constant DEFAULT_MEMBER_TYPE = "Default";
    string public defaultImageURL;

    // Track if this is the first mint
    bool public firstMint;

    event MintedNFT(address recipient, string memberTypeName, string tokenURI);
    event MembershipTypeChanged(address user, string newMemberType);
    event MemberRemoved(address user);
    event ExecutiveDowngraded(address downgradedExecutive, address downgrader);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Constructor is disabled - use initialize instead
     */
    constructor() ERC721("", "") {}

    /**
     * @dev Initialize the contract with org details and membership types
     */
    function initialize(
        address _owner, 
        string memory name_,
        string[] memory _memberTypeNames, 
        string[] memory _executiveRoleNames, 
        string memory _defaultImageURL
    ) external initializer {
        require(_owner != address(0), "Invalid owner");
        
        // Store token name and symbol for overriding the getter functions
        _tokenName = name_;
        _tokenSymbol = "MBR";
        
        owner = _owner;
        defaultImageURL = _defaultImageURL;
        
        // Initialize firstMint as true
        firstMint = true;
        
        for (uint256 i = 0; i < _memberTypeNames.length; i++) {
            memberTypeNames[i] = _memberTypeNames[i];
            memberTypeImages[_memberTypeNames[i]] = _defaultImageURL;
        }

        for (uint256 i = 0; i < _executiveRoleNames.length; i++) {
            isExecutiveRole[_executiveRoleNames[i]] = true;
        }
    }

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
     * @dev Modifier to restrict function access to the organization owner
     */
    modifier onlyOwner() {
        require(msg.sender == owner, "Not org owner");
        _;
    }

    modifier onlyExecutiveRole() {
        require(isExecutiveRole[memberTypeOf[msg.sender]], "Not an executive role");
        _;
    }

    modifier canMintCustomNFT() {
        // require is executive or is voting contract
        require(
            isExecutiveRole[memberTypeOf[msg.sender]] || msg.sender == electionContract,
            "Not an executive role or election contract"
        );
        _;
    }

    function setElectionContract(address _electionContract) public onlyOwner {
        require(electionContract == address(0), "Election contract already set");
        electionContract = _electionContract;
    }

    function setQuickJoin(address _quickJoin) public {
        require(!quickJoinSet, "QuickJoin already set");
        quickJoin = _quickJoin;
        quickJoinSet = true;
    }

    modifier onlyQuickJoin() {
        require(msg.sender == quickJoin, "Only QuickJoin can call this function");
        _;
    }

    function setMemberTypeImage(string memory memberTypeName, string memory imageURL) public onlyOwner {
        memberTypeImages[memberTypeName] = imageURL;
    }

    function checkMemberTypeByAddress(address user) public view returns (string memory) {
        require(bytes(memberTypeOf[user]).length > 0, "No member type found for user.");
        return memberTypeOf[user];
    }

    function checkIsExecutive(address user) public view returns (bool) {
        return isExecutiveRole[memberTypeOf[user]];
    }

    function mintNFT(address recipient, string memory memberTypeName) public canMintCustomNFT {
        require(bytes(memberTypeImages[memberTypeName]).length > 0, "Image for member type not set");
        string memory tokenURI = memberTypeImages[memberTypeName];
        uint256 tokenId = _nextTokenId++;
        _mint(recipient, tokenId);
        _setTokenURI(tokenId, tokenURI);
        memberTypeOf[recipient] = memberTypeName;
        emit MintedNFT(recipient, memberTypeName, tokenURI);
    }

    function changeMembershipType(address user, string memory newMemberType) public canMintCustomNFT {
        require(bytes(memberTypeImages[newMemberType]).length > 0, "Image for member type not set");
        memberTypeOf[user] = newMemberType;
        emit MembershipTypeChanged(user, newMemberType);
    }

    function giveUpExecutiveRole() public onlyExecutiveRole {
        memberTypeOf[msg.sender] = DEFAULT_MEMBER_TYPE;
        emit MembershipTypeChanged(msg.sender, DEFAULT_MEMBER_TYPE);
    }

    function removeMember(address user) public onlyExecutiveRole {
        require(bytes(memberTypeOf[user]).length > 0, "No member type found for user.");
        delete memberTypeOf[user];
        emit MemberRemoved(user);
    }

    function downgradeExecutive(address executive) public onlyExecutiveRole {
        require(isExecutiveRole[memberTypeOf[executive]], "User is not an executive.");
        require(
            block.timestamp >= lastDowngradeTime[msg.sender] + ONE_WEEK, 
            "Downgrade limit reached. Try again in a week."
        );

        memberTypeOf[executive] = DEFAULT_MEMBER_TYPE;
        lastDowngradeTime[msg.sender] = block.timestamp;
        emit ExecutiveDowngraded(executive, msg.sender);
    }

    function mintDefaultNFT(address newUser) public onlyQuickJoin {
        require(bytes(memberTypeOf[newUser]).length == 0, "User is already a member.");
        string memory tokenURI = defaultImageURL;
        uint256 tokenId = _nextTokenId++;
        _mint(newUser, tokenId);
        _setTokenURI(tokenId, tokenURI);
        if (firstMint) {
            memberTypeOf[newUser] = "Executive";
            firstMint = false;
            emit MintedNFT(newUser, "Executive", tokenURI);
        } else {
            memberTypeOf[newUser] = DEFAULT_MEMBER_TYPE;
            emit MintedNFT(newUser, DEFAULT_MEMBER_TYPE, tokenURI);
        }
    }

    function getQuickJoin() public view returns (address) {
        return quickJoin;
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
     * @dev Implementation of the IERC721 isMember function required by Voting contract
     */
    function isMember(address account) external view returns (bool) {
        return bytes(memberTypeOf[account]).length > 0;
    }
    
    /**
     * @dev Version identifier to help with testing upgrades
     */
    function version() external pure returns (string memory) {
        return "v1";
    }
}
