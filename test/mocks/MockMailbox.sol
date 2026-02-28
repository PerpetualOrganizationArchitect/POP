// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IMessageRecipient} from "../../src/crosschain/interfaces/IHyperlane.sol";

/// @title MockMailbox
/// @notice Synchronous Hyperlane mailbox mock for unit tests.
///         Immediately delivers messages to the recipient's handle() function.
contract MockMailbox {
    uint32 public localDomain;
    uint256 public messageCount;

    /// @dev Stores dispatched payloads for test assertions.
    struct DispatchedMessage {
        uint32 destinationDomain;
        bytes32 recipientAddress;
        bytes messageBody;
    }

    DispatchedMessage[] public dispatched;

    constructor(uint32 _localDomain) {
        localDomain = _localDomain;
    }

    function dispatch(uint32 destinationDomain, bytes32 recipientAddress, bytes calldata messageBody)
        external
        payable
        returns (bytes32)
    {
        dispatched.push(
            DispatchedMessage({
                destinationDomain: destinationDomain, recipientAddress: recipientAddress, messageBody: messageBody
            })
        );

        // Immediately deliver to the recipient (synchronous simulation)
        address target = address(uint160(uint256(recipientAddress)));
        IMessageRecipient(target).handle(localDomain, bytes32(uint256(uint160(msg.sender))), messageBody);

        unchecked {
            ++messageCount;
        }
        return keccak256(abi.encodePacked(messageCount, destinationDomain, recipientAddress));
    }

    function dispatchedCount() external view returns (uint256) {
        return dispatched.length;
    }
}
