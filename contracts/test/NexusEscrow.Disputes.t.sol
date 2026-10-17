// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { TestBase } from "./utils/TestBase.t.sol";
import { NexusEscrow } from "../src/NexusEscrow.sol";

contract NexusEscrowDisputesTest is TestBase {
    function test_RaiseDispute_ByBuyer_MarksMilestoneDisputed() public {
        uint256 id = _createAndFundNative(_singleMilestone(1 ether));

        vm.prank(buyer);
        escrow.raiseDispute(id);

        NexusEscrow.Milestone memory m = escrow.getMilestone(id, 0);
        assertEq(uint8(m.status), uint8(NexusEscrow.MilestoneStatus.Disputed));
    }

    function test_RaiseDispute_BySeller_MarksMilestoneDisputed() public {
        uint256 id = _createAndFundNative(_singleMilestone(1 ether));

        vm.prank(seller);
        escrow.raiseDispute(id);

        NexusEscrow.Milestone memory m = escrow.getMilestone(id, 0);
        assertEq(uint8(m.status), uint8(NexusEscrow.MilestoneStatus.Disputed));
    }

    function test_RaiseDispute_RevertWhen_NotParty() public {
        uint256 id = _createAndFundNative(_singleMilestone(1 ether));
        vm.prank(stranger);
        vm.expectRevert(NexusEscrow.NotParty.selector);
        escrow.raiseDispute(id);
    }

    function test_RaiseDispute_RevertWhen_NotActive() public {
        uint256 id = _createNativeAgreement(_singleMilestone(1 ether));
        vm.prank(buyer);
        vm.expectRevert(NexusEscrow.WrongState.selector);
        escrow.raiseDispute(id);
    }

    function test_RaiseDispute_RevertWhen_AlreadyDisputed() public {
        uint256 id = _createAndFundNative(_singleMilestone(1 ether));
        vm.prank(buyer);
        escrow.raiseDispute(id);

        vm.prank(seller);
        vm.expectRevert(NexusEscrow.WrongMilestoneState.selector);
        escrow.raiseDispute(id);
    }

    function test_ResolveDispute_EvenSplit() public {
        uint256 id = _createAndFundNative(_singleMilestone(1 ether));
        vm.prank(buyer);
        escrow.raiseDispute(id);

        uint256 buyerBefore = buyer.balance;
        uint256 sellerBefore = seller.balance;

        vm.prank(arbiter);
        escrow.resolveDispute(id, 5000); // 50/50

        uint256 buyerAmount = 0.5 ether;
        uint256 sellerGross = 0.5 ether;
        uint256 fee = (sellerGross * escrow.protocolFeeBps()) / escrow.BPS_DENOMINATOR();

        assertEq(buyer.balance, buyerBefore + buyerAmount);
        assertEq(seller.balance, sellerBefore + sellerGross - fee);
        assertEq(escrow.accruedFees(address(0)), fee);

        NexusEscrow.Milestone memory m = escrow.getMilestone(id, 0);
        assertEq(uint8(m.status), uint8(NexusEscrow.MilestoneStatus.Resolved));

        (,,,,,, NexusEscrow.AgreementStatus status,,,,) = escrow.agreements(id);
        assertEq(uint8(status), uint8(NexusEscrow.AgreementStatus.Completed));
    }

    function test_ResolveDispute_FullBuyerRefund_NoFeeCharged() public {
        uint256 id = _createAndFundNative(_singleMilestone(1 ether));
        vm.prank(seller);
        escrow.raiseDispute(id);

        uint256 buyerBefore = buyer.balance;

        vm.prank(arbiter);
        escrow.resolveDispute(id, 10_000); // 100% to buyer

        assertEq(buyer.balance, buyerBefore + 1 ether);
        assertEq(escrow.accruedFees(address(0)), 0);
    }

    function test_ResolveDispute_FullSellerAward() public {
        uint256 id = _createAndFundNative(_singleMilestone(1 ether));
        vm.prank(buyer);
        escrow.raiseDispute(id);

        uint256 sellerBefore = seller.balance;

        vm.prank(arbiter);
        escrow.resolveDispute(id, 0); // 100% to seller

        uint256 fee = (1 ether * uint256(escrow.protocolFeeBps())) / escrow.BPS_DENOMINATOR();
        assertEq(seller.balance, sellerBefore + 1 ether - fee);
    }

    function test_ResolveDispute_RevertWhen_NotArbiter() public {
        uint256 id = _createAndFundNative(_singleMilestone(1 ether));
        vm.prank(buyer);
        escrow.raiseDispute(id);

        vm.prank(buyer);
        vm.expectRevert(NexusEscrow.NotArbiter.selector);
        escrow.resolveDispute(id, 5000);
    }

    function test_ResolveDispute_RevertWhen_BpsOutOfRange() public {
        uint256 id = _createAndFundNative(_singleMilestone(1 ether));
        vm.prank(buyer);
        escrow.raiseDispute(id);

        vm.prank(arbiter);
        vm.expectRevert(NexusEscrow.BpsOutOfRange.selector);
        escrow.resolveDispute(id, 10_001);
    }

    function test_ResolveDispute_RevertWhen_NotDisputed() public {
        uint256 id = _createAndFundNative(_singleMilestone(1 ether));
        vm.prank(arbiter);
        vm.expectRevert(NexusEscrow.WrongMilestoneState.selector);
        escrow.resolveDispute(id, 5000);
    }

    function test_ResolveDispute_OnMiddleMilestone_AdvancesCorrectly() public {
        uint128[] memory milestones = _threeMilestones();
        uint256 id = _createAndFundNative(milestones);

        vm.prank(buyer);
        escrow.approveMilestone(id); // milestone 0 released

        vm.prank(buyer);
        escrow.raiseDispute(id); // dispute milestone 1

        vm.prank(arbiter);
        escrow.resolveDispute(id, 5000);

        (,,,,,,,,, uint8 milestoneCount, uint8 nextMilestone) = escrow.agreements(id);
        assertEq(nextMilestone, 2);
        assertEq(milestoneCount, 3);

        // milestone 2 still pending and can proceed normally
        vm.prank(buyer);
        escrow.approveMilestone(id);

        (,,,,,, NexusEscrow.AgreementStatus status,,,,) = escrow.agreements(id);
        assertEq(uint8(status), uint8(NexusEscrow.AgreementStatus.Completed));
    }

    // ---------------------------------------------------------------------
    // Double-resolution, race and partial-completion conservation
    // ---------------------------------------------------------------------

    function test_ResolveDispute_RevertWhen_AlreadyResolved() public {
        uint256 id = _createAndFundNative(_singleMilestone(1 ether));
        vm.prank(buyer);
        escrow.raiseDispute(id);
        vm.prank(arbiter);
        escrow.resolveDispute(id, 5000);

        vm.prank(arbiter);
        vm.expectRevert(NexusEscrow.WrongState.selector);
        escrow.resolveDispute(id, 5000);
    }

    function test_ResolveDispute_RevertWhen_MilestoneNotDisputed() public {
        uint256 id = _createAndFundNative(_singleMilestone(1 ether));

        vm.prank(arbiter);
        vm.expectRevert(NexusEscrow.WrongMilestoneState.selector);
        escrow.resolveDispute(id, 5000);

        // After a release, the cursor has advanced past the milestone: resolving
        // the old milestone is impossible and resolving the (nonexistent) new one
        // is a state error.
        vm.prank(buyer);
        escrow.approveMilestone(id);
        vm.prank(arbiter);
        vm.expectRevert(NexusEscrow.WrongState.selector);
        escrow.resolveDispute(id, 5000);
    }

    function test_RaiseDispute_RevertWhen_AgreementCompleted() public {
        uint256 id = _createAndFundNative(_singleMilestone(1 ether));
        vm.prank(buyer);
        escrow.approveMilestone(id);

        vm.prank(buyer);
        vm.expectRevert(NexusEscrow.WrongState.selector);
        escrow.raiseDispute(id);

        vm.prank(seller);
        vm.expectRevert(NexusEscrow.WrongState.selector);
        escrow.raiseDispute(id);
    }

    function test_PartialCompletion_DisputeFlow_ConservesTotal() public {
        uint128[] memory milestones = _threeMilestones();
        uint256 total = _sum(milestones);
        vm.deal(buyer, total);
        uint256 id = _createNativeAgreement(milestones);
        vm.prank(buyer);
        escrow.fund{ value: total }(id);

        uint256 buyerBefore = buyer.balance;
        uint256 sellerBefore = seller.balance;

        vm.prank(buyer);
        escrow.approveMilestone(id); // M0 released

        vm.prank(seller);
        escrow.raiseDispute(id); // M1 disputed (raised by seller)
        vm.prank(arbiter);
        escrow.resolveDispute(id, 3000); // 30% refunded

        vm.prank(buyer);
        escrow.approveMilestone(id); // M2 released

        (,,,,,, NexusEscrow.AgreementStatus status,,,,) = escrow.agreements(id);
        assertEq(uint8(status), uint8(NexusEscrow.AgreementStatus.Completed));

        uint256 sellerReceived = seller.balance - sellerBefore;
        uint256 buyerRefunded = buyer.balance - buyerBefore;
        uint256 fee = escrow.accruedFees(address(0));

        // buyer deposited `total`; afterwards: refunds + seller payouts + fees == total.
        assertEq(buyerRefunded + sellerReceived + fee, total, "partial completion not conserved");
        assertEq(address(escrow).balance, fee, "escrow retains only fees");
    }

    function test_ResolveDispute_RoundingBoundary_9999Bps() public {
        uint256 amount = 100_003;
        vm.deal(buyer, amount);
        uint256 id = _createAndFundNative(_singleMilestone(100_003));
        vm.prank(buyer);
        escrow.raiseDispute(id);

        uint256 buyerBefore = buyer.balance;
        uint256 sellerBefore = seller.balance;

        vm.prank(arbiter);
        escrow.resolveDispute(id, 9999);

        uint256 refunded = buyer.balance - buyerBefore;
        uint256 paid = seller.balance - sellerBefore;
        uint256 fee = escrow.accruedFees(address(0));

        assertEq(refunded + paid + fee, amount);
        assertLe(refunded, amount); // 1 bps to seller side, rounded down
    }

    function test_CancelVsDispute_Race_FundedAgreementDisputeWins() public {
        uint256 id = _createAndFundNative(_singleMilestone(1 ether));

        vm.prank(seller);
        vm.expectRevert(NexusEscrow.WrongState.selector);
        escrow.cancelBeforeFunding(id);

        vm.prank(buyer);
        escrow.raiseDispute(id);
        NexusEscrow.Milestone memory m = escrow.getMilestone(id, 0);
        assertEq(uint8(m.status), uint8(NexusEscrow.MilestoneStatus.Disputed));
    }

    function test_CancelVsDispute_Race_UnfundedCancelWins() public {
        uint256 id = _createNativeAgreement(_singleMilestone(1 ether));

        vm.prank(buyer);
        escrow.cancelBeforeFunding(id);

        vm.prank(buyer);
        vm.expectRevert(NexusEscrow.WrongState.selector);
        escrow.raiseDispute(id);
    }
}
