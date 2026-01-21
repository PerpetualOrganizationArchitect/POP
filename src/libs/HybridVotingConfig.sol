// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import "../HybridVoting.sol";
import "./VotingErrors.sol";

library HybridVotingConfig {
    bytes32 private constant _STORAGE_SLOT = 0x7a3e8e3d8e9c8f7b6a5d4c3b2a1908070605040302010009080706050403020a;

    uint8 public constant MAX_CLASSES = 8;

    event ClassesReplaced(
        uint256 indexed version, bytes32 indexed classesHash, HybridVoting.ClassConfig[] classes, uint64 timestamp
    );

    function _layout() private pure returns (HybridVoting.Layout storage s) {
        assembly {
            s.slot := _STORAGE_SLOT
        }
    }

    function setClasses(HybridVoting.ClassConfig[] calldata newClasses) external {
        if (newClasses.length == 0) revert VotingErrors.InvalidClassCount();
        if (newClasses.length > MAX_CLASSES) revert VotingErrors.TooManyClasses();

        uint256 totalSlice;
        for (uint256 i; i < newClasses.length;) {
            HybridVoting.ClassConfig calldata c = newClasses[i];
            if (c.slicePct == 0 || c.slicePct > 100) revert VotingErrors.InvalidSliceSum();
            totalSlice += c.slicePct;

            if (c.strategy == HybridVoting.ClassStrategy.ERC20_BAL) {
                if (c.asset == address(0)) revert VotingErrors.ZeroAddress();
            }
            unchecked {
                ++i;
            }
        }

        if (totalSlice != 100) revert VotingErrors.InvalidSliceSum();

        HybridVoting.Layout storage l = _layout();
        delete l.classes;
        for (uint256 i; i < newClasses.length;) {
            l.classes.push(newClasses[i]);
            unchecked {
                ++i;
            }
        }

        bytes32 classesHash = keccak256(abi.encode(newClasses));
        emit ClassesReplaced(block.number, classesHash, l.classes, uint64(block.timestamp));
    }

    function validateAndInitClasses(HybridVoting.ClassConfig[] calldata initialClasses) external {
        if (initialClasses.length == 0) revert VotingErrors.InvalidClassCount();
        if (initialClasses.length > MAX_CLASSES) revert VotingErrors.TooManyClasses();

        uint256 totalSlice;
        for (uint256 i; i < initialClasses.length;) {
            HybridVoting.ClassConfig calldata c = initialClasses[i];
            if (c.slicePct == 0 || c.slicePct > 100) revert VotingErrors.InvalidSliceSum();
            totalSlice += c.slicePct;

            if (c.strategy == HybridVoting.ClassStrategy.ERC20_BAL) {
                if (c.asset == address(0)) revert VotingErrors.ZeroAddress();
            }

            _layout().classes.push(initialClasses[i]);
            unchecked {
                ++i;
            }
        }

        if (totalSlice != 100) revert VotingErrors.InvalidSliceSum();

        HybridVoting.Layout storage l = _layout();
        bytes32 classesHash = keccak256(abi.encode(l.classes));
        emit ClassesReplaced(block.number, classesHash, l.classes, uint64(block.timestamp));
    }
}
