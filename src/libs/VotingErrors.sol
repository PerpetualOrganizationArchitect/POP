// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

library VotingErrors {
    error Unauthorized();
    error AlreadyVoted();
    error InvalidProposal();
    error VotingExpired();
    error VotingOpen();
    error InvalidIndex();
    error LengthMismatch();
    error DurationOutOfRange();
    error TooManyOptions();
    error TooManyCalls();
    error ZeroAddress();
    error InvalidMetadata();
    error RoleNotAllowed();
    error WeightSumNot100(uint256 sum);
    error InvalidWeight();
    error DuplicateIndex();
    error TargetNotAllowed();
    error TargetSelf();
    error InvalidTarget();
    error EmptyBatch();
    error InvalidQuorum();
    error Paused();
    error Overflow();
    error InvalidClassCount();
    error InvalidSliceSum();
    error TooManyClasses();
    error InvalidStrategy();
}
