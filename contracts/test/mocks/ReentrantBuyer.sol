// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { NexusEscrow } from "../../src/NexusEscrow.sol";

/// @dev Acts as a buyer and, upon receiving a native refund mid-`resolveDispute`,
///      attempts to reenter `approveMilestone` on the same agreement. Used to prove
///      the contract's single ReentrancyGuard lock blocks cross-function reentrancy.
contract ReentrantBuyer {
    NexusEscrow public immutable ESCROW;
    uint256 public agreementId;
    bool public attacked;
    bool public reentrancyReverted;

    constructor(NexusEscrow escrow_) {
        ESCROW = escrow_;
    }

    function createAgreement(
        address seller,
        address arbiter,
        address tokenAddr,
        uint128[] calldata milestoneAmounts,
        uint40 fundingDeadline
    ) external returns (uint256 id) {
        id = ESCROW.createAgreement(seller, arbiter, tokenAddr, milestoneAmounts, fundingDeadline);
        agreementId = id;
    }

    function fund(uint256 value) external {
        ESCROW.fund{ value: value }(agreementId);
    }

    function raiseDispute() external {
        ESCROW.raiseDispute(agreementId);
    }

    receive() external payable {
        if (!attacked) {
            attacked = true;
            try ESCROW.approveMilestone(agreementId) {
                reentrancyReverted = false;
            } catch {
                reentrancyReverted = true;
            }
        }
    }
}
