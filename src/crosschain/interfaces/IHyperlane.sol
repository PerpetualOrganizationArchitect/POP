// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal Hyperlane Mailbox interface — only the functions POP uses.
interface IMailbox {
    /// @notice Dispatch a message to a remote chain.
    /// @param destinationDomain  Hyperlane domain ID of the target chain.
    /// @param recipientAddress   Recipient address encoded as bytes32.
    /// @param messageBody        Arbitrary payload.
    /// @return messageId         Unique identifier for the dispatched message.
    function dispatch(uint32 destinationDomain, bytes32 recipientAddress, bytes calldata messageBody)
        external
        payable
        returns (bytes32 messageId);
}

/// @notice Callback interface implemented by contracts that receive Hyperlane messages.
interface IMessageRecipient {
    /// @param origin   Hyperlane domain ID of the source chain.
    /// @param sender   Sender address encoded as bytes32.
    /// @param message  The message payload.
    function handle(uint32 origin, bytes32 sender, bytes calldata message) external;
}
