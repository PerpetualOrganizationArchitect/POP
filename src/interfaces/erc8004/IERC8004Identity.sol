// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

/**
 * @title IERC8004Identity
 * @notice Interface for ERC-8004 Identity Registry (Trustless Agents)
 * @dev Based on ERC-721 with URIStorage extension for agent registration
 * @custom:reference https://eips.ethereum.org/EIPS/eip-8004
 */
interface IERC8004Identity {
    // ============ Events ============

    event Registered(uint256 indexed agentId, string agentURI, address indexed owner);
    event URIUpdated(uint256 indexed agentId, string newURI, address indexed updatedBy);
    event MetadataSet(
        uint256 indexed agentId, string indexed indexedMetadataKey, string metadataKey, bytes metadataValue
    );

    // ============ Structs ============

    struct MetadataEntry {
        string metadataKey;
        bytes metadataValue;
    }

    // ============ Registration ============

    function register(string calldata agentURI, MetadataEntry[] calldata metadata) external returns (uint256 agentId);
    function register(string calldata agentURI) external returns (uint256 agentId);
    function register() external returns (uint256 agentId);

    // ============ URI Management ============

    function setAgentURI(uint256 agentId, string calldata newURI) external;
    function tokenURI(uint256 agentId) external view returns (string memory);

    // ============ Metadata ============

    function getMetadata(uint256 agentId, string memory metadataKey) external view returns (bytes memory);
    function setMetadata(uint256 agentId, string memory metadataKey, bytes memory metadataValue) external;

    // ============ Agent Wallet ============

    function setAgentWallet(uint256 agentId, address newWallet, uint256 deadline, bytes calldata signature) external;
    function getAgentWallet(uint256 agentId) external view returns (address);
    function unsetAgentWallet(uint256 agentId) external;

    // ============ ERC-721 Standard ============

    function ownerOf(uint256 tokenId) external view returns (address);
    function balanceOf(address owner) external view returns (uint256);
}
