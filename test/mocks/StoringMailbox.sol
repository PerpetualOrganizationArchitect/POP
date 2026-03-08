// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title StoringMailbox
/// @notice Mock mailbox that stores dispatched messages WITHOUT auto-delivering.
///         Use for testing contracts that dispatch responses in handle() callbacks
///         where auto-delivery would fail due to cross-chain mailbox mismatch.
contract StoringMailbox {
    uint32 public localDomain;
    uint256 public messageCount;

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

        unchecked {
            ++messageCount;
        }
        return keccak256(abi.encodePacked(messageCount, destinationDomain, recipientAddress));
    }

    function dispatchedCount() external view returns (uint256) {
        return dispatched.length;
    }

    function getDispatched(uint256 index) external view returns (DispatchedMessage memory) {
        return dispatched[index];
    }
}
