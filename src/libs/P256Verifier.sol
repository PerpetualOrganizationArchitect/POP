// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

/**
 * @title P256Verifier
 * @author POA Team
 * @notice Library for secp256r1 (P-256) signature verification using EIP-7951 precompile
 * @dev This library provides gas-efficient P256 signature verification by:
 *      1. First attempting the EIP-7951 precompile at address 0x100
 *      2. Falling back to daimo-eth's deterministic verifier contract if precompile unavailable
 *
 *      EIP-7951 Specification (Fusaka upgrade, live Dec 3 2025):
 *      - Address: 0x100
 *      - Gas cost: 6900 gas (fixed, regardless of result)
 *      - Input: 160 bytes (messageHash || r || s || x || y)
 *      - Output valid: 32 bytes with value 1
 *      - Output invalid/error: empty bytes (NOT zero!)
 *
 *      EIP-7951 supersedes RIP-7212 with critical security fixes:
 *      - Point-at-infinity check (prevents non-deterministic behavior)
 *      - Modular comparison: r' ≡ r (mod n) for proper x-coordinate handling
 *
 *      Gas costs:
 *      - EIP-7951 precompile (L1): 6,900 gas
 *      - RIP-7212 precompile (L2s): 3,450 gas
 *      - Fallback contract: ~330,000 gas
 *
 *      L2 Support (RIP-7212 - ALREADY LIVE):
 *      These chains have native P256 precompile at 0x100 TODAY:
 *      - Arbitrum One/Nova
 *      - Optimism
 *      - Base
 *      - zkSync Era
 *      - Polygon PoS
 *      - Scroll
 *      - Linea
 *
 *      L1 Support (EIP-7951 - Fusaka upgrade):
 *      - Ethereum mainnet: December 3, 2025
 *
 *      Gas Optimization:
 *      For optimal gas, cache `isPrecompileAvailable()` at deployment and use
 *      `verifyWithHint()` with the cached value. This avoids:
 *      - Failed precompile calls on chains without precompile
 *      - Redundant fallback calls when precompile exists but signature is invalid
 *
 *      Example:
 *      ```solidity
 *      bool public immutable hasP256Precompile = P256Verifier.isPrecompileAvailable();
 *
 *      function validateSignature(...) internal view {
 *          return P256Verifier.verifyWithHint(hash, r, s, x, y, hasP256Precompile);
 *      }
 *      ```
 */
library P256Verifier {
    /*──────────────────────────── Constants ────────────────────────────*/

    /// @notice EIP-7951/RIP-7212 precompile address
    /// @dev Same address on L1 and all supported L2s
    address internal constant PRECOMPILE = address(0x100);

    /// @notice daimo-eth P256 verifier at deterministic CREATE2 address
    /// @dev Deployed at same address on all EVM chains via Safe Singleton Factory
    /// @dev See: https://github.com/daimo-eth/p256-verifier
    address internal constant FALLBACK_VERIFIER = 0xc2b78104907F722DABAc4C69f826a522B2754De4;

    /*──────────────────────────── Errors ───────────────────────────────*/

    /// @notice Thrown when signature verification fails
    error InvalidSignature();

    /// @notice Thrown when public key coordinates are invalid (zero)
    error InvalidPublicKey();

    /// @notice Thrown when signature components are invalid (zero or >= n)
    error InvalidSignatureComponents();

    /*──────────────────────────── Main Functions ──────────────────────*/

    /**
     * @notice Verify a secp256r1 signature
     * @param messageHash The 32-byte hash of the message that was signed
     * @param r The r component of the signature (32 bytes)
     * @param s The s component of the signature (32 bytes)
     * @param x The x coordinate of the public key (32 bytes)
     * @param y The y coordinate of the public key (32 bytes)
     * @return valid True if the signature is valid, false otherwise
     * @dev Attempts precompile first, falls back to contract verifier
     */
    function verify(bytes32 messageHash, bytes32 r, bytes32 s, bytes32 x, bytes32 y)
        internal
        view
        returns (bool valid)
    {
        // Pack input for precompile (160 bytes total)
        // Format: messageHash(32) || r(32) || s(32) || x(32) || y(32)
        bytes memory input = abi.encodePacked(messageHash, r, s, x, y);

        // Try EIP-7951 precompile first (at 0x100)
        // Per EIP-7951: returns 32 bytes with value 1 if valid, empty bytes if invalid
        (bool success, bytes memory result) = PRECOMPILE.staticcall(input);

        if (success && result.length == 32) {
            // Only returns 32 bytes for valid signatures (value will be 1)
            // Invalid signatures return empty bytes, not 0
            return abi.decode(result, (uint256)) == 1;
        }

        // Precompile returned empty (invalid sig OR precompile doesn't exist)
        // Try daimo-eth fallback verifier for chains without native precompile
        (success, result) = FALLBACK_VERIFIER.staticcall(input);

        if (success && result.length == 32) {
            return abi.decode(result, (uint256)) == 1;
        }

        // Both methods returned empty - signature is invalid
        return false;
    }

    /**
     * @notice Verify a signature and revert if invalid
     * @param messageHash The 32-byte hash of the message that was signed
     * @param r The r component of the signature
     * @param s The s component of the signature
     * @param x The x coordinate of the public key
     * @param y The y coordinate of the public key
     * @dev Reverts with InvalidSignature if verification fails
     */
    function verifyOrRevert(bytes32 messageHash, bytes32 r, bytes32 s, bytes32 x, bytes32 y) internal view {
        if (!verify(messageHash, r, s, x, y)) {
            revert InvalidSignature();
        }
    }

    /**
     * @notice Verify using precompile only (no fallback)
     * @param messageHash The 32-byte hash of the message that was signed
     * @param r The r component of the signature (32 bytes)
     * @param s The s component of the signature (32 bytes)
     * @param x The x coordinate of the public key (32 bytes)
     * @param y The y coordinate of the public key (32 bytes)
     * @return valid True if the signature is valid, false otherwise
     * @dev Use this when you know the precompile is available (e.g., cached at deployment).
     *      Saves ~330k gas on invalid signatures by not trying fallback.
     *      Returns false if precompile is unavailable OR signature is invalid.
     */
    function verifyWithPrecompile(bytes32 messageHash, bytes32 r, bytes32 s, bytes32 x, bytes32 y)
        internal
        view
        returns (bool valid)
    {
        bytes memory input = abi.encodePacked(messageHash, r, s, x, y);
        (bool success, bytes memory result) = PRECOMPILE.staticcall(input);

        if (success && result.length == 32) {
            return abi.decode(result, (uint256)) == 1;
        }
        return false;
    }

    /**
     * @notice Verify using fallback verifier only (no precompile)
     * @param messageHash The 32-byte hash of the message that was signed
     * @param r The r component of the signature (32 bytes)
     * @param s The s component of the signature (32 bytes)
     * @param x The x coordinate of the public key (32 bytes)
     * @param y The y coordinate of the public key (32 bytes)
     * @return valid True if the signature is valid, false otherwise
     * @dev Use this on chains without precompile to save the failed precompile call gas.
     *      The daimo-eth verifier costs ~330k gas regardless of result.
     */
    function verifyWithFallback(bytes32 messageHash, bytes32 r, bytes32 s, bytes32 x, bytes32 y)
        internal
        view
        returns (bool valid)
    {
        bytes memory input = abi.encodePacked(messageHash, r, s, x, y);
        (bool success, bytes memory result) = FALLBACK_VERIFIER.staticcall(input);

        if (success && result.length == 32) {
            return abi.decode(result, (uint256)) == 1;
        }
        return false;
    }

    /**
     * @notice Verify using cached precompile availability hint
     * @param messageHash The 32-byte hash of the message that was signed
     * @param r The r component of the signature (32 bytes)
     * @param s The s component of the signature (32 bytes)
     * @param x The x coordinate of the public key (32 bytes)
     * @param y The y coordinate of the public key (32 bytes)
     * @param hasPrecompile Whether the precompile is known to be available
     * @return valid True if the signature is valid, false otherwise
     * @dev Use this with a cached `isPrecompileAvailable()` result for optimal gas.
     *      Example: cache the result in an immutable at deployment time.
     */
    function verifyWithHint(bytes32 messageHash, bytes32 r, bytes32 s, bytes32 x, bytes32 y, bool hasPrecompile)
        internal
        view
        returns (bool valid)
    {
        if (hasPrecompile) {
            return verifyWithPrecompile(messageHash, r, s, x, y);
        }
        return verifyWithFallback(messageHash, r, s, x, y);
    }

    /**
     * @notice Check if the P256 precompile is available on this chain
     * @return available True if the precompile is available
     * @dev Useful for gas estimation and debugging
     */
    function isPrecompileAvailable() internal view returns (bool available) {
        // The osaka P256 precompile only returns 32 bytes for VALID signatures
        // It returns empty for invalid signatures (unlike the EIP spec which says return 0)
        // So we must use a known valid NIST P-256 test vector to detect availability

        // NIST P-256 test vector (valid signature)
        bytes memory testInput = abi.encodePacked(
            bytes32(0x44acf6b7e36c1342c2c5897204fe09504e1e2efb1a900377dbc4e7a6a133ec56), // messageHash
            bytes32(0xf3ac8061b514795b8843e3d6629527ed2afd6b1f6a555a7acabb5e6f79c8c2ac), // r
            bytes32(0x8bf77819ca05a6b2786c76262bf7371cef97b218e96f175a3ccdda2acc058903), // s
            bytes32(0x1ccbe91c075fc7f4f033bfa248db8fccd3565de94bbfb12f3c59ff46c271bf83), // x
            bytes32(0xce4014c68811f9a21a1fdb2c0e6113e06db7ca93b7404e78dc7ccd5ca89a4ca9) // y
        );

        (bool success, bytes memory result) = PRECOMPILE.staticcall(testInput);

        // Precompile exists if call succeeded, returned 32 bytes, and value is 1 (valid)
        if (success && result.length == 32) {
            return abi.decode(result, (uint256)) == 1;
        }
        return false;
    }

    /**
     * @notice Estimate gas cost for P256 verification on current chain
     * @return gasCost Estimated gas cost for verify()
     * @dev Returns costs per specification:
     *      - 6900 for L1 precompile (EIP-7951, Fusaka+)
     *      - 3450 for L2 precompile (RIP-7212)
     *      - 350000 for fallback contract (daimo-eth)
     */
    function estimateVerificationGas() internal view returns (uint256 gasCost) {
        if (isPrecompileAvailable()) {
            // Precompile available - check if L1 or L2 based on chain ID
            // L1 mainnet = 1, L2s have higher chain IDs
            if (block.chainid == 1) {
                return 6900; // EIP-7951 exact gas cost
            }
            return 3450; // RIP-7212 exact gas cost (L2s)
        }
        return 350000; // Fallback contract gas cost
    }

    /*──────────────────────────── Validation Helpers ──────────────────*/

    /**
     * @notice Validate public key coordinates
     * @param x The x coordinate of the public key
     * @param y The y coordinate of the public key
     * @return valid True if the public key is valid (non-zero)
     * @dev Note: This only checks for zero values. Full curve validation
     *      is performed by the verifier itself.
     */
    function isValidPublicKey(bytes32 x, bytes32 y) internal pure returns (bool valid) {
        return x != bytes32(0) && y != bytes32(0);
    }

    /**
     * @notice Validate signature components
     * @param r The r component of the signature
     * @param s The s component of the signature
     * @return valid True if the signature components are valid (non-zero)
     * @dev Note: This only checks for zero values. Full range validation
     *      is performed by the verifier itself.
     */
    function isValidSignature(bytes32 r, bytes32 s) internal pure returns (bool valid) {
        return r != bytes32(0) && s != bytes32(0);
    }
}
