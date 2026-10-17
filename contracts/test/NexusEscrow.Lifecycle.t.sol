// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { TestBase } from "./utils/TestBase.t.sol";
import { NexusEscrow } from "../src/NexusEscrow.sol";

contract NexusEscrowLifecycleTest is TestBase {
    // ---------------------------------------------------------------------
    // createAgreement
    // ---------------------------------------------------------------------

    function test_CreateAgreement_StoresFields() public {
        uint128[] memory milestones = _threeMilestones();
        uint256 id = _createNativeAgreement(milestones);

        (
            address storedBuyer,
            address storedSeller,
            address storedArbiter,
            address storedToken,
            uint128 totalAmount,
            uint16 feeBps,
            NexusEscrow.AgreementStatus status,,,
            uint8 milestoneCount,
            uint8 nextMilestone
        ) = escrow.agreements(id);

        assertEq(storedBuyer, buyer);
        assertEq(storedSeller, seller);
        assertEq(storedArbiter, arbiter);
        assertEq(storedToken, address(0));
        assertEq(totalAmount, _sum(milestones));
        assertEq(feeBps, escrow.protocolFeeBps());
        assertEq(uint8(status), uint8(NexusEscrow.AgreementStatus.AwaitingFunding));
        assertEq(milestoneCount, 3);
        assertEq(nextMilestone, 0);
    }

    function test_CreateAgreement_RevertWhen_SellerIsSelf() public {
        vm.prank(buyer);
        vm.expectRevert(NexusEscrow.InvalidAddress.selector);
        escrow.createAgreement(buyer, arbiter, address(0), _singleMilestone(1 ether), 0);
    }

    function test_CreateAgreement_RevertWhen_ArbiterIsBuyerOrSeller() public {
        vm.startPrank(buyer);
        vm.expectRevert(NexusEscrow.InvalidAddress.selector);
        escrow.createAgreement(seller, buyer, address(0), _singleMilestone(1 ether), 0);

        vm.expectRevert(NexusEscrow.InvalidAddress.selector);
        escrow.createAgreement(seller, seller, address(0), _singleMilestone(1 ether), 0);
        vm.stopPrank();
    }

    function test_CreateAgreement_RevertWhen_NoMilestones() public {
        vm.prank(buyer);
        vm.expectRevert(NexusEscrow.InvalidMilestones.selector);
        escrow.createAgreement(seller, arbiter, address(0), new uint128[](0), 0);
    }

    function test_CreateAgreement_RevertWhen_TooManyMilestones() public {
        uint128[] memory milestones = new uint128[](51);
        for (uint256 i = 0; i < 51; ++i) {
            milestones[i] = 1 ether;
        }
        vm.prank(buyer);
        vm.expectRevert(NexusEscrow.InvalidMilestones.selector);
        escrow.createAgreement(seller, arbiter, address(0), milestones, 0);
    }

    function test_CreateAgreement_RevertWhen_ZeroAmountMilestone() public {
        uint128[] memory milestones = new uint128[](2);
        milestones[0] = 1 ether;
        milestones[1] = 0;
        vm.prank(buyer);
        vm.expectRevert(NexusEscrow.InvalidAmount.selector);
        escrow.createAgreement(seller, arbiter, address(0), milestones, 0);
    }

    function test_GetMilestones_ReturnsFullArray() public {
        uint128[] memory milestones = _threeMilestones();
        uint256 id = _createNativeAgreement(milestones);

        NexusEscrow.Milestone[] memory stored = escrow.getMilestones(id);
        assertEq(stored.length, milestones.length);
        for (uint256 i = 0; i < milestones.length; ++i) {
            assertEq(stored[i].amount, milestones[i]);
            assertEq(uint8(stored[i].status), uint8(NexusEscrow.MilestoneStatus.Pending));
        }
    }

    function test_CreateAgreement_RevertWhen_DeadlineInPast() public {
        vm.warp(1_000_000);
        vm.prank(buyer);
        vm.expectRevert(NexusEscrow.DeadlinePassed.selector);
        escrow.createAgreement(
            seller, arbiter, address(0), _singleMilestone(1 ether), uint40(block.timestamp - 1)
        );
    }

    // ---------------------------------------------------------------------
    // fund
    // ---------------------------------------------------------------------

    function test_Fund_Native_ActivatesAgreement() public {
        uint256 id = _createNativeAgreement(_singleMilestone(1 ether));

        vm.prank(buyer);
        escrow.fund{ value: 1 ether }(id);

        (,,,,,, NexusEscrow.AgreementStatus status,,,,) = escrow.agreements(id);
        assertEq(uint8(status), uint8(NexusEscrow.AgreementStatus.Active));
        assertEq(address(escrow).balance, 1 ether);
    }

    function test_Fund_Native_RevertWhen_WrongValue() public {
        uint256 id = _createNativeAgreement(_singleMilestone(1 ether));
        vm.prank(buyer);
        vm.expectRevert(NexusEscrow.NativeValueMismatch.selector);
        escrow.fund{ value: 0.5 ether }(id);
    }

    function test_Fund_RevertWhen_NotBuyer() public {
        uint256 id = _createNativeAgreement(_singleMilestone(1 ether));
        vm.deal(stranger, 1 ether);
        vm.prank(stranger);
        vm.expectRevert(NexusEscrow.NotBuyer.selector);
        escrow.fund{ value: 1 ether }(id);
    }

    function test_Fund_RevertWhen_AlreadyActive() public {
        uint256 id = _createAndFundNative(_singleMilestone(1 ether));
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        vm.expectRevert(NexusEscrow.WrongState.selector);
        escrow.fund{ value: 1 ether }(id);
    }

    function test_Fund_RevertWhen_DeadlinePassed() public {
        uint40 deadline = uint40(block.timestamp + 1 days);
        uint256 id = _createAgreement(address(0), _singleMilestone(1 ether), deadline);

        vm.warp(deadline + 1);
        vm.prank(buyer);
        vm.expectRevert(NexusEscrow.DeadlinePassed.selector);
        escrow.fund{ value: 1 ether }(id);
    }

    function test_Fund_ERC20_TransfersTokens() public {
        uint256 id = _createAndFundToken(_singleMilestone(1 ether));
        assertEq(token.balanceOf(address(escrow)), 1 ether);

        (,,,,,, NexusEscrow.AgreementStatus status,,,,) = escrow.agreements(id);
        assertEq(uint8(status), uint8(NexusEscrow.AgreementStatus.Active));
    }

    function test_Fund_ERC20_RevertWhen_NativeValueSent() public {
        uint256 id = _createAgreement(address(token), _singleMilestone(1 ether), 0);
        vm.deal(buyer, 1 ether);
        vm.startPrank(buyer);
        token.approve(address(escrow), 1 ether);
        vm.expectRevert(NexusEscrow.NativeValueMismatch.selector);
        escrow.fund{ value: 1 ether }(id);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------------
    // approveMilestone
    // ---------------------------------------------------------------------

    function test_ApproveMilestone_PaysSellerMinusFee_Native() public {
        uint256 id = _createAndFundNative(_singleMilestone(1 ether));
        uint256 sellerBefore = seller.balance;

        vm.prank(buyer);
        escrow.approveMilestone(id);

        uint256 fee = (1 ether * uint256(escrow.protocolFeeBps())) / escrow.BPS_DENOMINATOR();
        assertEq(seller.balance, sellerBefore + 1 ether - fee);
        assertEq(escrow.accruedFees(address(0)), fee);
    }

    function test_ApproveMilestone_PaysSellerMinusFee_ERC20() public {
        uint256 id = _createAndFundToken(_singleMilestone(1 ether));

        vm.prank(buyer);
        escrow.approveMilestone(id);

        uint256 fee = (1 ether * uint256(escrow.protocolFeeBps())) / escrow.BPS_DENOMINATOR();
        assertEq(token.balanceOf(seller), 1 ether - fee);
        assertEq(escrow.accruedFees(address(token)), fee);
    }

    function test_ApproveMilestone_MultiMilestone_ReleasesInOrderAndCompletes() public {
        uint128[] memory milestones = _threeMilestones();
        uint256 id = _createAndFundNative(milestones);

        for (uint256 i = 0; i < milestones.length; ++i) {
            uint256 sellerBefore = seller.balance;
            vm.prank(buyer);
            escrow.approveMilestone(id);

            uint256 fee =
                (uint256(milestones[i]) * escrow.protocolFeeBps()) / escrow.BPS_DENOMINATOR();
            assertEq(seller.balance, sellerBefore + milestones[i] - fee);

            (,,,,,,,,, uint8 milestoneCount, uint8 nextMilestone) = escrow.agreements(id);
            assertEq(nextMilestone, i + 1);

            NexusEscrow.AgreementStatus expectedStatus = (i + 1 == milestoneCount)
                ? NexusEscrow.AgreementStatus.Completed
                : NexusEscrow.AgreementStatus.Active;
            (,,,,,, NexusEscrow.AgreementStatus status,,,,) = escrow.agreements(id);
            assertEq(uint8(status), uint8(expectedStatus));
        }
    }

    function test_ApproveMilestone_RevertWhen_NotBuyer() public {
        uint256 id = _createAndFundNative(_singleMilestone(1 ether));
        vm.prank(seller);
        vm.expectRevert(NexusEscrow.NotBuyer.selector);
        escrow.approveMilestone(id);
    }

    function test_ApproveMilestone_RevertWhen_NotActive() public {
        uint256 id = _createNativeAgreement(_singleMilestone(1 ether));
        vm.prank(buyer);
        vm.expectRevert(NexusEscrow.WrongState.selector);
        escrow.approveMilestone(id);
    }

    function test_ApproveMilestone_RevertWhen_AlreadyReleased() public {
        uint256 id = _createAndFundNative(_singleMilestone(1 ether));
        vm.startPrank(buyer);
        escrow.approveMilestone(id);
        vm.expectRevert(NexusEscrow.WrongState.selector);
        escrow.approveMilestone(id);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------------
    // cancelBeforeFunding
    // ---------------------------------------------------------------------

    function test_CancelBeforeFunding_ByBuyer() public {
        uint256 id = _createNativeAgreement(_singleMilestone(1 ether));
        vm.prank(buyer);
        escrow.cancelBeforeFunding(id);
        (,,,,,, NexusEscrow.AgreementStatus status,,,,) = escrow.agreements(id);
        assertEq(uint8(status), uint8(NexusEscrow.AgreementStatus.Cancelled));
    }

    function test_CancelBeforeFunding_BySeller() public {
        uint256 id = _createNativeAgreement(_singleMilestone(1 ether));
        vm.prank(seller);
        escrow.cancelBeforeFunding(id);
        (,,,,,, NexusEscrow.AgreementStatus status,,,,) = escrow.agreements(id);
        assertEq(uint8(status), uint8(NexusEscrow.AgreementStatus.Cancelled));
    }

    function test_CancelBeforeFunding_RevertWhen_StrangerBeforeDeadline() public {
        uint256 id = _createNativeAgreement(_singleMilestone(1 ether));
        vm.prank(stranger);
        vm.expectRevert(NexusEscrow.NotAuthorized.selector);
        escrow.cancelBeforeFunding(id);
    }

    function test_CancelBeforeFunding_StrangerAllowedAfterDeadline() public {
        uint40 deadline = uint40(block.timestamp + 1 days);
        uint256 id = _createAgreement(address(0), _singleMilestone(1 ether), deadline);

        vm.warp(deadline + 1);
        vm.prank(stranger);
        escrow.cancelBeforeFunding(id);

        (,,,,,, NexusEscrow.AgreementStatus status,,,,) = escrow.agreements(id);
        assertEq(uint8(status), uint8(NexusEscrow.AgreementStatus.Cancelled));
    }

    function test_CancelBeforeFunding_RevertWhen_AlreadyFunded() public {
        uint256 id = _createAndFundNative(_singleMilestone(1 ether));
        vm.prank(buyer);
        vm.expectRevert(NexusEscrow.WrongState.selector);
        escrow.cancelBeforeFunding(id);
    }

    // ---------------------------------------------------------------------
    // Boundary, overflow, ordering and unknown-id behaviour
    // ---------------------------------------------------------------------

    function test_CreateAgreement_RevertWhen_MilestoneSumOverflowsUint128() public {
        uint128[] memory milestones = new uint128[](2);
        milestones[0] = type(uint128).max;
        milestones[1] = 1; // sum = 2^128, one past the storable max

        vm.prank(buyer);
        vm.expectRevert(NexusEscrow.InvalidAmount.selector);
        escrow.createAgreement(seller, arbiter, address(0), milestones, 0);
    }

    function test_CreateAgreement_MaxMilestones_Allowed() public {
        uint128[] memory milestones = new uint128[](50);
        for (uint256 i = 0; i < 50; ++i) {
            milestones[i] = 1; // tiny amounts keep the sum bounded
        }
        uint256 id = _createNativeAgreement(milestones);
        (,,,,,,,,, uint8 count,) = escrow.agreements(id);
        assertEq(count, 50);
    }

    function test_Fund_ExactlyAtDeadline_IsAllowed() public {
        uint40 deadline = uint40(block.timestamp + 1 days);
        uint256 id = _createAgreement(address(0), _singleMilestone(1 ether), deadline);

        vm.warp(deadline); // boundary: fund checks `>` so equality passes
        vm.prank(buyer);
        escrow.fund{ value: 1 ether }(id);

        (,,,,,, NexusEscrow.AgreementStatus status,,,,) = escrow.agreements(id);
        assertEq(uint8(status), uint8(NexusEscrow.AgreementStatus.Active));
    }

    function test_CancelBeforeFunding_ExactlyAtDeadline_StrangerStillBlocked() public {
        uint40 deadline = uint40(block.timestamp + 1 days);
        uint256 id = _createAgreement(address(0), _singleMilestone(1 ether), deadline);

        vm.warp(deadline); // cancel uses `>`; equality is not yet "passed"
        vm.prank(stranger);
        vm.expectRevert(NexusEscrow.NotAuthorized.selector);
        escrow.cancelBeforeFunding(id);
    }

    function test_MilestoneOrder_CursorOnly_NoBypass() public {
        uint256 id = _createAndFundNative(_threeMilestones());

        // While milestone 0 is Pending, indices 1 and 2 are unreachable: the only
        // state-changing paths act on `nextMilestone`, and after release the cursor
        // advances by exactly one. Prove the post-conditions.
        vm.prank(buyer);
        escrow.approveMilestone(id);

        NexusEscrow.Milestone[] memory milestones = escrow.getMilestones(id);
        assertEq(uint8(milestones[0].status), uint8(NexusEscrow.MilestoneStatus.Released));
        assertEq(uint8(milestones[1].status), uint8(NexusEscrow.MilestoneStatus.Pending));
        assertEq(uint8(milestones[2].status), uint8(NexusEscrow.MilestoneStatus.Pending));

        (,,,,,,,,, uint8 count, uint8 next) = escrow.agreements(id);
        assertEq(next, 1);
        assertEq(count, 3);

        // The cursor cannot be aimed back at index 0: approving again necessarily
        // releases index 1 (in order), never re-releases index 0.
        vm.prank(buyer);
        escrow.approveMilestone(id);
        milestones = escrow.getMilestones(id);
        assertEq(uint8(milestones[0].status), uint8(NexusEscrow.MilestoneStatus.Released));
        assertEq(uint8(milestones[1].status), uint8(NexusEscrow.MilestoneStatus.Released));
        assertEq(uint8(milestones[2].status), uint8(NexusEscrow.MilestoneStatus.Pending));
        (,,,,,,,,, count, next) = escrow.agreements(id);
        assertEq(next, 2);
    }

    function test_UnknownAgreement_NoValuePaths() public {
        uint256 ghostId = 999;

        vm.deal(stranger, 1 ether);
        vm.prank(stranger);
        vm.expectRevert(NexusEscrow.NotBuyer.selector);
        escrow.fund{ value: 1 ether }(ghostId);

        // approveMilestone's caller check runs before its state check.
        vm.prank(stranger);
        vm.expectRevert(NexusEscrow.NotBuyer.selector);
        escrow.approveMilestone(ghostId);

        vm.prank(stranger);
        vm.expectRevert(NexusEscrow.WrongState.selector);
        escrow.raiseDispute(ghostId);

        vm.prank(stranger);
        vm.expectRevert(NexusEscrow.NotAuthorized.selector);
        escrow.cancelBeforeFunding(ghostId);

        // Views return zeroed data — integrators must bound ids by nextAgreementId().
        (address buyerAddr,,,,,,,,,,) = escrow.agreements(ghostId);
        assertEq(buyerAddr, address(0));
        assertEq(escrow.getMilestones(ghostId).length, 0);
    }

    function test_GetMilestone_RevertWhen_IndexOutOfBounds() public {
        uint256 id = _createNativeAgreement(_singleMilestone(1 ether));
        vm.expectRevert();
        escrow.getMilestone(id, 1);
    }
}
