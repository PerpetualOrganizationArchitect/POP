// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {P256Verifier} from "./P256Verifier.sol";

/**
 * @title WebAuthnLib
 * @author POA Team
 * @notice Library for WebAuthn/Passkey signature parsing and verification
 * @dev Implements WebAuthn assertion verification for ERC-4337 account abstraction
 *
 *      WebAuthn Signature Flow:
 *      1. Authenticator signs: sha256(authenticatorData || sha256(clientDataJSON))
 *      2. clientDataJSON contains base64url-encoded challenge (the userOpHash)
 *      3. authenticatorData contains rpIdHash, flags, and signCount
 *
 *      This library verifies:
 *      - The challenge in clientDataJSON matches the expected value
 *      - The authenticator flags indicate user presence/verification
 *      - The P256 signature over the constructed message is valid
 *
 *      References:
 *      - WebAuthn spec: https://www.w3.org/TR/webauthn-2/
 *      - FIDO2 CTAP: https://fidoalliance.org/specs/fido-v2.0-rd-20180702/fido-client-to-authenticator-protocol-v2.0-rd-20180702.html
 */
library WebAuthnLib {
    /*──────────────────────────── Constants ────────────────────────────*/

    /// @notice Authenticator data flag: User Present (UP)
    uint8 internal constant FLAG_USER_PRESENT = 0x01;

    /// @notice Authenticator data flag: User Verified (UV)
    uint8 internal constant FLAG_USER_VERIFIED = 0x04;

    /// @notice Authenticator data flag: Attested credential data included
    uint8 internal constant FLAG_ATTESTED_CREDENTIAL = 0x40;

    /// @notice Authenticator data flag: Extension data included
    uint8 internal constant FLAG_EXTENSION_DATA = 0x80;

    /// @notice Minimum authenticator data length (rpIdHash + flags + signCount)
    uint256 internal constant MIN_AUTH_DATA_LENGTH = 37;

    /// @notice Base64URL alphabet for decoding challenge
    bytes internal constant BASE64URL_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

    /*──────────────────────────── Errors ───────────────────────────────*/

    /// @notice Thrown when authenticator data is too short
    error AuthDataTooShort();

    /// @notice Thrown when user presence flag is not set
    error UserNotPresent();

    /// @notice Thrown when the challenge doesn't match expected value
    error ChallengeMismatch();

    /// @notice Thrown when clientDataJSON is malformed
    error MalformedClientData();

    /// @notice Thrown when the signature is invalid
    error InvalidWebAuthnSignature();

    /// @notice Thrown when signCount indicates replay attack
    error SignCountTooLow();

    /*──────────────────────────── Structs ──────────────────────────────*/

    /**
     * @notice WebAuthn signature data structure
     * @param authenticatorData Raw authenticator data bytes
     * @param clientDataJSON Raw client data JSON string as bytes
     * @param challengeIndex Index where "challenge":"<value>" starts in clientDataJSON
     * @param typeIndex Index where "type":"webauthn.get" starts in clientDataJSON
     * @param r P256 signature r component
     * @param s P256 signature s component
     */
    struct WebAuthnAuth {
        bytes authenticatorData;
        bytes clientDataJSON;
        uint256 challengeIndex;
        uint256 typeIndex;
        bytes32 r;
        bytes32 s;
    }

    /**
     * @notice Parsed authenticator data
     * @param rpIdHash SHA-256 hash of the relying party ID
     * @param flags Authenticator flags byte
     * @param signCount Signature counter (anti-replay)
     */
    struct AuthenticatorData {
        bytes32 rpIdHash;
        uint8 flags;
        uint32 signCount;
    }

    /*──────────────────────────── Main Functions ──────────────────────*/

    /**
     * @notice Verify a WebAuthn signature
     * @param auth The WebAuthn authentication data
     * @param challenge The expected challenge (typically userOpHash)
     * @param x Public key x coordinate
     * @param y Public key y coordinate
     * @param requireUserVerification If true, require UV flag to be set
     * @return valid True if the signature is valid
     */
    function verify(
        WebAuthnAuth memory auth,
        bytes32 challenge,
        bytes32 x,
        bytes32 y,
        bool requireUserVerification
    ) internal view returns (bool valid) {
        // 1. Validate authenticator data length
        if (auth.authenticatorData.length < MIN_AUTH_DATA_LENGTH) {
            return false;
        }

        // 2. Parse and validate authenticator flags
        uint8 flags = uint8(auth.authenticatorData[32]);

        // User presence is always required
        if ((flags & FLAG_USER_PRESENT) == 0) {
            return false;
        }

        // User verification may be required
        if (requireUserVerification && (flags & FLAG_USER_VERIFIED) == 0) {
            return false;
        }

        // 3. Verify challenge in clientDataJSON
        if (!_verifyChallenge(auth.clientDataJSON, auth.challengeIndex, challenge)) {
            return false;
        }

        // 4. Verify type is "webauthn.get"
        if (!_verifyType(auth.clientDataJSON, auth.typeIndex)) {
            return false;
        }

        // 5. Compute the message hash
        // message = sha256(authenticatorData || sha256(clientDataJSON))
        bytes32 clientDataHash = sha256(auth.clientDataJSON);
        bytes32 messageHash = sha256(abi.encodePacked(auth.authenticatorData, clientDataHash));

        // 6. Verify P256 signature
        return P256Verifier.verify(messageHash, auth.r, auth.s, x, y);
    }

    /**
     * @notice Verify a WebAuthn signature and revert if invalid
     * @param auth The WebAuthn authentication data
     * @param challenge The expected challenge
     * @param x Public key x coordinate
     * @param y Public key y coordinate
     * @param requireUserVerification If true, require UV flag
     */
    function verifyOrRevert(
        WebAuthnAuth memory auth,
        bytes32 challenge,
        bytes32 x,
        bytes32 y,
        bool requireUserVerification
    ) internal view {
        if (!verify(auth, challenge, x, y, requireUserVerification)) {
            revert InvalidWebAuthnSignature();
        }
    }

    /**
     * @notice Verify signature with signCount anti-replay check
     * @param auth The WebAuthn authentication data
     * @param challenge The expected challenge
     * @param x Public key x coordinate
     * @param y Public key y coordinate
     * @param requireUserVerification If true, require UV flag
     * @param lastSignCount The last known signCount for this credential
     * @return valid True if valid
     * @return newSignCount The new signCount from this authentication
     */
    function verifyWithSignCount(
        WebAuthnAuth memory auth,
        bytes32 challenge,
        bytes32 x,
        bytes32 y,
        bool requireUserVerification,
        uint32 lastSignCount
    ) internal view returns (bool valid, uint32 newSignCount) {
        // Parse signCount from authenticator data (bytes 33-36, big-endian)
        if (auth.authenticatorData.length < MIN_AUTH_DATA_LENGTH) {
            return (false, 0);
        }

        newSignCount = uint32(bytes4(
            abi.encodePacked(
                auth.authenticatorData[33],
                auth.authenticatorData[34],
                auth.authenticatorData[35],
                auth.authenticatorData[36]
            )
        ));

        // SignCount must be greater than last known value (if non-zero)
        // Note: signCount of 0 means the authenticator doesn't support counters
        if (lastSignCount > 0 && newSignCount > 0 && newSignCount <= lastSignCount) {
            return (false, newSignCount);
        }

        valid = verify(auth, challenge, x, y, requireUserVerification);
        return (valid, newSignCount);
    }

    /*──────────────────────────── Parsing Functions ───────────────────*/

    /**
     * @notice Parse authenticator data
     * @param authData Raw authenticator data bytes
     * @return parsed Parsed authenticator data struct
     */
    function parseAuthenticatorData(bytes calldata authData)
        internal
        pure
        returns (AuthenticatorData memory parsed)
    {
        if (authData.length < MIN_AUTH_DATA_LENGTH) {
            revert AuthDataTooShort();
        }

        // rpIdHash: bytes 0-31
        parsed.rpIdHash = bytes32(authData[0:32]);

        // flags: byte 32
        parsed.flags = uint8(authData[32]);

        // signCount: bytes 33-36 (big-endian uint32)
        parsed.signCount = uint32(bytes4(authData[33:37]));
    }

    /**
     * @notice Extract the challenge from clientDataJSON
     * @param clientDataJSON The client data JSON bytes
     * @param challengeIndex Index where challenge value starts
     * @return challenge The decoded challenge bytes32
     * @dev The challenge in clientDataJSON is base64url-encoded
     */
    function extractChallenge(bytes calldata clientDataJSON, uint256 challengeIndex)
        internal
        pure
        returns (bytes32 challenge)
    {
        // Find the end quote of the challenge value
        uint256 i = challengeIndex;
        while (i < clientDataJSON.length && clientDataJSON[i] != '"') {
            i++;
        }

        // Extract and decode the base64url challenge
        bytes memory encoded = clientDataJSON[challengeIndex:i];
        bytes memory decoded = _base64UrlDecode(encoded);

        if (decoded.length != 32) {
            revert ChallengeMismatch();
        }

        challenge = bytes32(decoded);
    }

    /*──────────────────────────── Internal Functions ──────────────────*/

    /**
     * @notice Verify the challenge in clientDataJSON matches expected value
     * @param clientDataJSON The client data JSON bytes
     * @param challengeIndex Index where challenge value starts (after "challenge":")
     * @param expectedChallenge The expected challenge value
     * @return valid True if challenge matches
     */
    function _verifyChallenge(
        bytes memory clientDataJSON,
        uint256 challengeIndex,
        bytes32 expectedChallenge
    ) private pure returns (bool valid) {
        // The challenge in clientDataJSON is base64url-encoded
        // We need to decode it and compare with expected

        // Find the end of the challenge string (look for closing quote)
        uint256 endIndex = challengeIndex;
        while (endIndex < clientDataJSON.length && clientDataJSON[endIndex] != '"') {
            endIndex++;
        }

        if (endIndex >= clientDataJSON.length) {
            return false;
        }

        // Extract the base64url-encoded challenge (manual copy since memory doesn't support slices)
        uint256 challengeLen = endIndex - challengeIndex;
        bytes memory encodedChallenge = new bytes(challengeLen);
        for (uint256 i = 0; i < challengeLen; i++) {
            encodedChallenge[i] = clientDataJSON[challengeIndex + i];
        }

        // Decode and compare
        bytes memory decodedChallenge = _base64UrlDecode(encodedChallenge);

        if (decodedChallenge.length != 32) {
            return false;
        }

        return bytes32(decodedChallenge) == expectedChallenge;
    }

    /**
     * @notice Verify the type in clientDataJSON is "webauthn.get"
     * @param clientDataJSON The client data JSON bytes
     * @param typeIndex Index where type value starts (after "type":")
     * @return valid True if type is "webauthn.get"
     */
    function _verifyType(bytes memory clientDataJSON, uint256 typeIndex) private pure returns (bool valid) {
        // Expected: "webauthn.get"
        bytes memory expected = bytes("webauthn.get");

        if (typeIndex + expected.length > clientDataJSON.length) {
            return false;
        }

        for (uint256 i = 0; i < expected.length; i++) {
            if (clientDataJSON[typeIndex + i] != expected[i]) {
                return false;
            }
        }

        return true;
    }

    /**
     * @notice Decode a base64url-encoded string
     * @param encoded The base64url-encoded bytes
     * @return decoded The decoded bytes
     * @dev Base64url uses '-' and '_' instead of '+' and '/', and no padding
     */
    function _base64UrlDecode(bytes memory encoded) private pure returns (bytes memory decoded) {
        if (encoded.length == 0) {
            return new bytes(0);
        }

        // Calculate output length (account for missing padding)
        uint256 paddedLength = encoded.length;
        if (paddedLength % 4 != 0) {
            paddedLength += 4 - (paddedLength % 4);
        }

        uint256 decodedLength = (paddedLength * 3) / 4;

        // Adjust for actual padding that would be needed
        uint256 missingPadding = paddedLength - encoded.length;
        if (missingPadding > 0) {
            decodedLength -= missingPadding;
        }

        decoded = new bytes(decodedLength);

        uint256 outIdx = 0;
        uint256 buffer = 0;
        uint256 bitsCollected = 0;

        for (uint256 i = 0; i < encoded.length; i++) {
            uint8 char = uint8(encoded[i]);
            uint8 value;

            // Decode base64url character
            if (char >= 65 && char <= 90) {
                // A-Z
                value = char - 65;
            } else if (char >= 97 && char <= 122) {
                // a-z
                value = char - 97 + 26;
            } else if (char >= 48 && char <= 57) {
                // 0-9
                value = char - 48 + 52;
            } else if (char == 45) {
                // '-' (base64url)
                value = 62;
            } else if (char == 95) {
                // '_' (base64url)
                value = 63;
            } else {
                continue; // Skip invalid characters
            }

            buffer = (buffer << 6) | value;
            bitsCollected += 6;

            if (bitsCollected >= 8) {
                bitsCollected -= 8;
                if (outIdx < decodedLength) {
                    decoded[outIdx++] = bytes1(uint8(buffer >> bitsCollected));
                }
                buffer &= (1 << bitsCollected) - 1;
            }
        }
    }
}
