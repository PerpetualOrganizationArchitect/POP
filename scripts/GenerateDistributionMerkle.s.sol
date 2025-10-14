// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {IERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title GenerateDistributionMerkle
 * @notice Script to generate merkle tree for revenue distributions
 * @dev Queries token balances at checkpoint and builds merkle tree
 *
 * Usage:
 *   forge script scripts/GenerateDistributionMerkle.s.sol:GenerateDistributionMerkle \
 *     --sig "run(address,uint256,uint256)" \
 *     <tokenAddress> <checkpointBlock> <distributionAmount>
 */
contract GenerateDistributionMerkle is Script {
    struct Holder {
        address account;
        uint256 votes;
        uint256 share;
    }

    /**
     * @notice Main entry point for generating merkle tree
     * @param tokenAddress Address of the ERC20Votes token
     * @param checkpointBlock Block number to snapshot balances
     * @param distributionAmount Total amount to distribute
     */
    function run(
        address tokenAddress,
        uint256 checkpointBlock,
        uint256 distributionAmount
    ) external {
        console.log("=== Generating Distribution Merkle Tree ===");
        console.log("Token:", tokenAddress);
        console.log("Checkpoint Block:", checkpointBlock);
        console.log("Distribution Amount:", distributionAmount);
        console.log("");

        // Get token interface
        IERC20Votes token = IERC20Votes(tokenAddress);

        // Get total supply at checkpoint
        uint256 totalSupply = token.getPastTotalSupply(checkpointBlock);
        console.log("Total Supply at Checkpoint:", totalSupply);

        if (totalSupply == 0) {
            console.log("ERROR: Total supply is zero at checkpoint");
            revert("Zero total supply");
        }

        // Get holders from Transfer events (simplified - in production use The Graph or indexer)
        address[] memory holderAddresses = _getHoldersFromEnv();

        if (holderAddresses.length == 0) {
            console.log("ERROR: No holders provided. Set HOLDERS environment variable.");
            console.log("Example: HOLDERS=0x123...,0x456...,0x789...");
            revert("No holders");
        }

        console.log("Number of holders:", holderAddresses.length);
        console.log("");

        // Build holder data with votes and shares
        Holder[] memory holders = new Holder[](holderAddresses.length);
        uint256 totalVotes = 0;

        console.log("=== Calculating Shares ===");
        for (uint256 i = 0; i < holderAddresses.length; i++) {
            address holder = holderAddresses[i];
            uint256 votes = token.getPastVotes(holder, checkpointBlock);

            holders[i] = Holder({
                account: holder,
                votes: votes,
                share: 0  // Calculate below
            });

            totalVotes += votes;
            console.log("Holder", i, ":", holder);
            console.log("  Votes:", votes);
        }

        console.log("");
        console.log("Total Votes:", totalVotes);

        if (totalVotes != totalSupply) {
            console.log("WARNING: Total votes != total supply");
            console.log("This may indicate not all holders are included");
        }

        // Calculate shares
        uint256 totalAllocated = 0;
        for (uint256 i = 0; i < holders.length; i++) {
            if (holders[i].votes > 0) {
                holders[i].share = (distributionAmount * holders[i].votes) / totalSupply;
                totalAllocated += holders[i].share;
                console.log("  Share:", holders[i].share);
            }
        }

        console.log("");
        console.log("Total Allocated:", totalAllocated);
        console.log("Dust (rounding error):", distributionAmount - totalAllocated);
        console.log("");

        // Build merkle tree
        console.log("=== Building Merkle Tree ===");
        bytes32[] memory leaves = new bytes32[](holders.length);

        for (uint256 i = 0; i < holders.length; i++) {
            leaves[i] = keccak256(bytes.concat(keccak256(abi.encode(holders[i].account, holders[i].share))));
            console.log("Leaf", i, ":", vm.toString(leaves[i]));
        }

        bytes32 merkleRoot = _buildMerkleRoot(leaves);

        console.log("");
        console.log("=== Merkle Root ===");
        console.log(vm.toString(merkleRoot));
        console.log("");

        // Generate proofs for each holder
        console.log("=== Generating Proofs ===");
        for (uint256 i = 0; i < holders.length; i++) {
            bytes32[] memory proof = _generateProof(leaves, i);

            console.log("Holder", i, "(", holders[i].account, "):");
            console.log("  Amount:", holders[i].share);
            console.log("  Proof length:", proof.length);

            for (uint256 j = 0; j < proof.length; j++) {
                console.log("    ", vm.toString(proof[j]));
            }

            // Verify proof
            bytes32 leaf = leaves[i];
            bool valid = MerkleProof.verify(proof, merkleRoot, leaf);
            console.log("  Proof valid:", valid);

            if (!valid) {
                console.log("  ERROR: Invalid proof generated!");
            }
            console.log("");
        }

        // Write output to JSON file
        _writeOutputFile(merkleRoot, holders, leaves);

        console.log("=== Generation Complete ===");
        console.log("Output written to: distribution-merkle.json");
    }

    /**
     * @notice Get holder addresses from environment variable
     * @dev In production, use event indexing (The Graph, etc.)
     */
    function _getHoldersFromEnv() internal view returns (address[] memory) {
        string memory holdersStr = vm.envOr("HOLDERS", string(""));

        if (bytes(holdersStr).length == 0) {
            return new address[](0);
        }

        // Simple comma-separated parsing
        // Note: This is a simplified implementation
        // In production, use proper CSV parsing or indexer
        string[] memory parts = vm.split(holdersStr, ",");
        address[] memory holders = new address[](parts.length);

        for (uint256 i = 0; i < parts.length; i++) {
            holders[i] = vm.parseAddress(parts[i]);
        }

        return holders;
    }

    /**
     * @notice Build merkle root from leaves
     * @dev Simple implementation for small trees
     */
    function _buildMerkleRoot(bytes32[] memory leaves) internal pure returns (bytes32) {
        uint256 n = leaves.length;
        if (n == 0) return bytes32(0);
        if (n == 1) return leaves[0];

        // Build tree bottom-up
        bytes32[] memory currentLevel = leaves;

        while (currentLevel.length > 1) {
            uint256 nextLevelSize = (currentLevel.length + 1) / 2;
            bytes32[] memory nextLevel = new bytes32[](nextLevelSize);

            for (uint256 i = 0; i < nextLevelSize; i++) {
                uint256 leftIdx = i * 2;
                uint256 rightIdx = leftIdx + 1;

                if (rightIdx < currentLevel.length) {
                    nextLevel[i] = _hashPair(currentLevel[leftIdx], currentLevel[rightIdx]);
                } else {
                    nextLevel[i] = currentLevel[leftIdx];
                }
            }

            currentLevel = nextLevel;
        }

        return currentLevel[0];
    }

    /**
     * @notice Generate merkle proof for a leaf at given index
     */
    function _generateProof(bytes32[] memory leaves, uint256 index) internal pure returns (bytes32[] memory) {
        uint256 n = leaves.length;
        if (n == 0 || index >= n) return new bytes32[](0);
        if (n == 1) return new bytes32[](0);

        // Calculate proof depth
        uint256 depth = 0;
        uint256 temp = n;
        while (temp > 1) {
            temp = (temp + 1) / 2;
            depth++;
        }

        bytes32[] memory proof = new bytes32[](depth);
        uint256 proofIdx = 0;

        bytes32[] memory currentLevel = leaves;
        uint256 currentIndex = index;

        while (currentLevel.length > 1) {
            uint256 nextLevelSize = (currentLevel.length + 1) / 2;
            bytes32[] memory nextLevel = new bytes32[](nextLevelSize);

            // Determine sibling index
            uint256 siblingIdx = currentIndex % 2 == 0 ? currentIndex + 1 : currentIndex - 1;

            if (siblingIdx < currentLevel.length) {
                proof[proofIdx++] = currentLevel[siblingIdx];
            }

            // Build next level
            for (uint256 i = 0; i < nextLevelSize; i++) {
                uint256 leftIdx = i * 2;
                uint256 rightIdx = leftIdx + 1;

                if (rightIdx < currentLevel.length) {
                    nextLevel[i] = _hashPair(currentLevel[leftIdx], currentLevel[rightIdx]);
                } else {
                    nextLevel[i] = currentLevel[leftIdx];
                }
            }

            currentLevel = nextLevel;
            currentIndex = currentIndex / 2;
        }

        // Trim proof to actual size
        bytes32[] memory trimmedProof = new bytes32[](proofIdx);
        for (uint256 i = 0; i < proofIdx; i++) {
            trimmedProof[i] = proof[i];
        }

        return trimmedProof;
    }

    /**
     * @notice Hash a pair of nodes in the merkle tree
     * @dev Sorts hashes to ensure deterministic ordering
     */
    function _hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    /**
     * @notice Write output to JSON file
     */
    function _writeOutputFile(bytes32 merkleRoot, Holder[] memory holders, bytes32[] memory leaves) internal {
        string memory json = "{";

        // Add merkle root
        json = string.concat(json, '"merkleRoot":"', vm.toString(merkleRoot), '",');

        // Add holders array
        json = string.concat(json, '"holders":[');

        for (uint256 i = 0; i < holders.length; i++) {
            if (i > 0) json = string.concat(json, ",");

            json = string.concat(json, "{");
            json = string.concat(json, '"address":"', vm.toString(holders[i].account), '",');
            json = string.concat(json, '"votes":', vm.toString(holders[i].votes), ',');
            json = string.concat(json, '"share":', vm.toString(holders[i].share), ',');

            // Generate and add proof
            bytes32[] memory proof = _generateProof(leaves, i);
            json = string.concat(json, '"proof":[');

            for (uint256 j = 0; j < proof.length; j++) {
                if (j > 0) json = string.concat(json, ",");
                json = string.concat(json, '"', vm.toString(proof[j]), '"');
            }

            json = string.concat(json, "]}");
        }

        json = string.concat(json, "]}");

        // Write to file
        vm.writeFile("distribution-merkle.json", json);
    }
}
