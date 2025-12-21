// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.24;

import {IPaymaster} from "./interfaces/IPaymaster.sol";
import {IEntryPoint} from "./interfaces/IEntryPoint.sol";
import {PackedUserOperation, UserOpLib} from "./interfaces/PackedUserOperation.sol";
import {IHats} from "lib/hats-protocol/src/Interfaces/IHats.sol";
import {IERC165} from "lib/openzeppelin-contracts/contracts/utils/introspection/IERC165.sol";

// Storage structs matching PaymasterHub
struct Config {
    address hats;
    uint256 adminHatId;
    uint256 operatorHatId;
    bool paused;
    uint8 version;
    uint24 reserved;
}

struct FeeCaps {
    uint256 maxFeePerGas;
    uint256 maxPriorityFeePerGas;
    uint32 maxCallGas;
    uint32 maxVerificationGas;
    uint32 maxPreVerificationGas;
}

struct Rule {
    uint32 maxCallGasHint;
    bool allowed;
}

struct Budget {
    uint128 capPerEpoch;
    uint128 usedInEpoch;
    uint32 epochLen;
    uint32 epochStart;
}

struct Bounty {
    bool enabled;
    uint96 maxBountyWeiPerOp;
    uint16 pctBpCap;
    uint144 totalPaid;
}

// Interface for PaymasterHub Storage Getters
interface IPaymasterHubStorage {
    function getConfig() external view returns (Config memory);
    function getBudget(bytes32 key) external view returns (Budget memory);
    function getRule(address target, bytes4 selector) external view returns (Rule memory);
    function getFeeCaps() external view returns (FeeCaps memory);
    function getBountyConfig() external view returns (Bounty memory);
    function ENTRY_POINT() external view returns (address);
}

/**
 * @title PaymasterHubLens
 * @author POA Engineering
 * @notice View-only lens contract for PaymasterHub to reduce main contract bytecode size
 * @dev Calls storage getters on PaymasterHub to read state and implement view logic
 */
contract PaymasterHubLens {
    using UserOpLib for bytes32;

    // ============ Custom Errors ============
    error InvalidRuleId();
    error InvalidPaymasterData();
    error ZeroAddress();

    // ============ Constants ============
    uint8 private constant PAYMASTER_DATA_VERSION = 1;
    uint8 private constant SUBJECT_TYPE_ACCOUNT = 0x00;
    uint8 private constant SUBJECT_TYPE_HAT = 0x01;

    uint32 private constant RULE_ID_GENERIC = 0x00000000;
    uint32 private constant RULE_ID_EXECUTOR = 0x00000001;
    uint32 private constant RULE_ID_COARSE = 0x000000FF;

    // ============ Immutable ============
    IPaymasterHubStorage public immutable hub;

    // ============ Constructor ============
    constructor(address _hub) {
        if (_hub == address(0)) revert ZeroAddress();
        hub = IPaymasterHubStorage(_hub);
    }

    // ============ View Functions ============

    function budgetOf(bytes32 subjectKey) external view returns (Budget memory) {
        Budget memory budget = hub.getBudget(subjectKey);

        // Calculate current epoch if needed
        uint256 currentTime = block.timestamp;
        if (currentTime >= budget.epochStart + budget.epochLen && budget.epochLen > 0) {
            uint32 epochsPassed = uint32((currentTime - budget.epochStart) / budget.epochLen);
            return Budget({
                capPerEpoch: budget.capPerEpoch,
                usedInEpoch: 0, // Reset after epoch roll
                epochLen: budget.epochLen,
                epochStart: budget.epochStart + (epochsPassed * budget.epochLen)
            });
        }

        return budget;
    }

    function ruleOf(address target, bytes4 selector) external view returns (Rule memory) {
        return hub.getRule(target, selector);
    }

    function remaining(bytes32 subjectKey) external view returns (uint256) {
        Budget memory budget = hub.getBudget(subjectKey);

        // Check if epoch needs rolling
        if (block.timestamp >= budget.epochStart + budget.epochLen && budget.epochLen > 0) {
            return budget.capPerEpoch; // Full budget available after epoch roll
        }

        return budget.capPerEpoch > budget.usedInEpoch ? budget.capPerEpoch - budget.usedInEpoch : 0;
    }

    function isAllowed(address target, bytes4 selector) external view returns (bool) {
        return hub.getRule(target, selector).allowed;
    }

    function config() external view returns (Config memory) {
        return hub.getConfig();
    }

    function feeCaps() external view returns (FeeCaps memory) {
        return hub.getFeeCaps();
    }

    function bountyInfo() external view returns (Bounty memory) {
        return hub.getBountyConfig();
    }

    function entryPointDeposit() external view returns (uint256) {
        address entryPoint = hub.ENTRY_POINT();
        return IEntryPoint(entryPoint).balanceOf(address(hub));
    }

    function bountyBalance() external view returns (uint256) {
        return address(hub).balance;
    }

    /**
     * @notice Check if a UserOperation would be valid without state changes
     */
    function wouldValidate(PackedUserOperation calldata userOp, uint256 maxCost)
        external
        view
        returns (bool valid, string memory reason)
    {
        // Check pause state
        Config memory cfg = hub.getConfig();
        if (cfg.paused) return (false, "Paused");

        // Decode paymasterAndData
        (uint8 version, uint8 subjectType, bytes20 subjectId, uint32 ruleId,) =
            _decodePaymasterData(userOp.paymasterAndData);

        if (version != PAYMASTER_DATA_VERSION) return (false, "InvalidVersion");

        // Check subject eligibility
        bytes32 subjectKey;
        if (subjectType == SUBJECT_TYPE_ACCOUNT) {
            if (address(subjectId) != userOp.sender) return (false, "Ineligible");
            subjectKey = keccak256(abi.encodePacked(subjectType, subjectId));
        } else if (subjectType == SUBJECT_TYPE_HAT) {
            uint256 hatId = uint256(bytes32(subjectId));
            if (!IHats(cfg.hats).isWearerOfHat(userOp.sender, hatId)) {
                return (false, "Ineligible");
            }
            subjectKey = keccak256(abi.encodePacked(subjectType, subjectId));
        } else {
            return (false, "InvalidSubjectType");
        }

        // Check rules
        (address target, bytes4 selector) = _extractTargetSelector(userOp, ruleId);
        if (!hub.getRule(target, selector).allowed) {
            return (false, "RuleDenied");
        }

        // Check budget
        Budget memory budget = hub.getBudget(subjectKey);
        uint256 currentTime = block.timestamp;
        uint128 available = budget.capPerEpoch;

        if (currentTime < budget.epochStart + budget.epochLen) {
            available = budget.capPerEpoch > budget.usedInEpoch ? budget.capPerEpoch - budget.usedInEpoch : 0;
        }

        if (maxCost > available) return (false, "BudgetExceeded");

        return (true, "Valid");
    }

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == type(IPaymaster).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    // ============ Helper Functions (copied from PaymasterHub) ============

    function _decodePaymasterData(bytes calldata paymasterAndData)
        private
        pure
        returns (uint8 version, uint8 subjectType, bytes20 subjectId, uint32 ruleId, uint64 mailboxCommit8)
    {
        if (paymasterAndData.length < 54) revert InvalidPaymasterData();

        // Skip first 20 bytes (paymaster address) and decode the rest
        version = uint8(paymasterAndData[20]);
        subjectType = uint8(paymasterAndData[21]);

        // Extract bytes20 subjectId from bytes 22-41
        assembly {
            subjectId := calldataload(add(paymasterAndData.offset, 22))
        }

        // Extract ruleId from bytes 42-45
        ruleId = uint32(bytes4(paymasterAndData[42:46]));

        // Extract mailboxCommit8 from bytes 46-53
        mailboxCommit8 = uint64(bytes8(paymasterAndData[46:54]));
    }

    function _extractTargetSelector(PackedUserOperation calldata userOp, uint32 ruleId)
        private
        pure
        returns (address target, bytes4 selector)
    {
        bytes calldata callData = userOp.callData;

        if (callData.length < 4) revert InvalidPaymasterData();

        if (ruleId == RULE_ID_GENERIC) {
            // ERC-4337 account execute patterns (SimpleAccount, PasskeyAccount, etc.)
            selector = bytes4(callData[0:4]);

            // Check for execute(address,uint256,bytes) - 0xb61d27f6
            // Used by SimpleAccount, PasskeyAccount, and most ERC-4337 wallets
            if (selector == 0xb61d27f6 && callData.length >= 0x64) {
                assembly {
                    // Extract target address at offset 0x04
                    target := calldataload(add(callData.offset, 0x04))

                    // Read the bytes data offset pointer at position 0x44
                    // This offset is relative to the start of params (0x04)
                    let dataOffset := calldataload(add(callData.offset, 0x44))

                    // Calculate where the actual bytes data starts:
                    // 0x04 (params start) + dataOffset + 0x20 (skip length field)
                    let dataStart := add(add(0x04, dataOffset), 0x20)

                    // Only extract inner selector if data is within bounds
                    if lt(dataStart, callData.length) {
                        selector := calldataload(add(callData.offset, dataStart))
                    }
                }
                selector = bytes4(selector);
            }
            // Check for executeBatch(address[],bytes[]) - 0x18dfb3c7 (SimpleAccount pattern)
            else if (selector == 0x18dfb3c7) {
                target = userOp.sender;
            }
            // Check for executeBatch(address[],uint256[],bytes[]) - 0x47e1da2a (PasskeyAccount pattern)
            else if (selector == 0x47e1da2a) {
                target = userOp.sender;
            } else {
                target = userOp.sender;
            }
        } else if (ruleId == RULE_ID_EXECUTOR) {
            // Custom Executor pattern
            target = userOp.sender;
            selector = bytes4(callData[0:4]);
        } else if (ruleId == RULE_ID_COARSE) {
            // Coarse mode: only check account's selector
            target = userOp.sender;
            selector = bytes4(callData[0:4]);
        } else {
            revert InvalidRuleId();
        }
    }
}
