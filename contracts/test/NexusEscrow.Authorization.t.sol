// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { TestBase } from "./utils/TestBase.t.sol";
import { NexusEscrow } from "../src/NexusEscrow.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

/// @notice Full caller-authorization matrix and privilege-boundary tests: who may
///         call what, what privileged actors cannot do, and that roles cannot be
///         confused at creation time.
contract NexusEscrowAuthorizationTest is TestBase {
    // ---------------------------------------------------------------------
    // Creation-time role validation
    // ---------------------------------------------------------------------

    function test_Create_RevertWhen_SellerZero() public {
        vm.prank(buyer);
        vm.expectRevert(NexusEscrow.InvalidAddress.selector);
        escrow.createAgreement(address(0), arbiter, address(0), _singleMilestone(1 ether), 0);
    }

    function test_Create_RevertWhen_ArbiterZero() public {
        vm.prank(buyer);
        vm.expectRevert(NexusEscrow.InvalidAddress.selector);
        escrow.createAgreement(seller, address(0), address(0), _singleMilestone(1 ether), 0);
    }

    function test_Create_RevertWhen_ArbiterEqualsBuyer() public {
        vm.prank(buyer);
        vm.expectRevert(NexusEscrow.InvalidAddress.selector);
        escrow.createAgreement(seller, buyer, address(0), _singleMilestone(1 ether), 0);
    }

    function test_Create_RevertWhen_ArbiterEqualsSeller() public {
        vm.prank(buyer);
        vm.expectRevert(NexusEscrow.InvalidAddress.selector);
        escrow.createAgreement(seller, seller, address(0), _singleMilestone(1 ether), 0);
    }

    function test_Create_RevertWhen_BuyerEqualsSeller() public {
        vm.prank(buyer);
        vm.expectRevert(NexusEscrow.InvalidAddress.selector);
        escrow.createAgreement(buyer, arbiter, address(0), _singleMilestone(1 ether), 0);
    }

    // ---------------------------------------------------------------------
    // Caller matrix — active agreement
    // ---------------------------------------------------------------------

    function test_Impersonation_FundBySellerAndStranger() public {
        uint256 id = _createNativeAgreement(_singleMilestone(1 ether));
        address[4] memory callers = [seller, stranger, arbiter, owner];
        for (uint256 i = 0; i < callers.length; ++i) {
            vm.deal(callers[i], 1 ether);
            vm.prank(callers[i]);
            vm.expectRevert(NexusEscrow.NotBuyer.selector);
            escrow.fund{ value: 1 ether }(id);
        }

        (,,,,,, NexusEscrow.AgreementStatus status,,,,) = escrow.agreements(id);
        assertEq(uint8(status), uint8(NexusEscrow.AgreementStatus.AwaitingFunding));
    }

    function test_Impersonation_ApproveBySellerArbiterStrangerOwner() public {
        uint256 id = _createAndFundNative(_singleMilestone(1 ether));

        address[4] memory callers = [seller, arbiter, stranger, owner];
        for (uint256 i = 0; i < callers.length; ++i) {
            vm.prank(callers[i]);
            vm.expectRevert(NexusEscrow.NotBuyer.selector);
            escrow.approveMilestone(id);
        }

        assertEq(address(escrow).balance, 1 ether, "escrow balance changed on failed calls");
    }

    function test_Impersonation_RaiseDisputeByArbiterStrangerOwner() public {
        uint256 id = _createAndFundNative(_singleMilestone(1 ether));

        address[3] memory callers = [arbiter, stranger, owner];
        for (uint256 i = 0; i < callers.length; ++i) {
            vm.prank(callers[i]);
            vm.expectRevert(NexusEscrow.NotParty.selector);
            escrow.raiseDispute(id);
        }
    }

    function test_Impersonation_ResolveByBuyerSellerStrangerOwner() public {
        uint256 id = _createAndFundNative(_singleMilestone(1 ether));
        vm.prank(buyer);
        escrow.raiseDispute(id);

        address[4] memory callers = [buyer, seller, stranger, owner];
        for (uint256 i = 0; i < callers.length; ++i) {
            vm.prank(callers[i]);
            vm.expectRevert(NexusEscrow.NotArbiter.selector);
            escrow.resolveDispute(id, 5000);
        }
    }

    function test_Unauthorized_CancelByStrangerBeforeDeadline() public {
        uint256 id = _createNativeAgreement(_singleMilestone(1 ether));
        vm.prank(stranger);
        vm.expectRevert(NexusEscrow.NotAuthorized.selector);
        escrow.cancelBeforeFunding(id);
    }

    function test_Unauthorized_WithdrawFeesByEveryoneElse() public {
        uint256 id = _createAndFundNative(_singleMilestone(1 ether));
        vm.prank(buyer);
        escrow.approveMilestone(id);

        address[4] memory callers = [buyer, seller, arbiter, owner];
        for (uint256 i = 0; i < callers.length; ++i) {
            vm.prank(callers[i]);
            vm.expectRevert(NexusEscrow.NotAuthorized.selector);
            escrow.withdrawFees(address(0));
        }
        assertGt(escrow.accruedFees(address(0)), 0, "fees unexpectedly withdrawn");
    }

    // ---------------------------------------------------------------------
    // Owner cannot seize principal
    // ---------------------------------------------------------------------

    function test_Owner_CannotTouchEscrowedPrincipal() public {
        _createAndFundNative(_singleMilestone(1 ether));
        uint256 escrowBefore = address(escrow).balance;

        // The owner has no fund-moving entry point at all: withdrawFees is reserved
        // for the fee recipient.
        vm.prank(owner);
        vm.expectRevert(NexusEscrow.NotAuthorized.selector);
        escrow.withdrawFees(address(0));

        // Even the fee recipient gets nothing until a fee is actually accrued.
        vm.prank(feeRecipient);
        vm.expectRevert(NexusEscrow.NothingToWithdraw.selector);
        escrow.withdrawFees(address(0));

        assertEq(address(escrow).balance, escrowBefore);
    }

    function test_FeeRecipient_CanOnlyWithdrawAccruedFees() public {
        // Total 6 ether across three milestones; release only the first (1 ether).
        uint256 id = _createAndFundNative(_threeMilestones());
        vm.prank(buyer);
        escrow.approveMilestone(id);

        uint256 fee = escrow.accruedFees(address(0));
        assertEq(fee, 0.01 ether);

        vm.prank(feeRecipient);
        escrow.withdrawFees(address(0));

        // Escrow still holds the untranched second and third milestones exactly.
        assertEq(address(escrow).balance, 5 ether);
        assertEq(feeRecipient.balance, fee);

        // The fee recipient cannot withdraw anything more.
        vm.prank(feeRecipient);
        vm.expectRevert(NexusEscrow.NothingToWithdraw.selector);
        escrow.withdrawFees(address(0));
    }

    // ---------------------------------------------------------------------
    // Ownable2Step boundary
    // ---------------------------------------------------------------------

    function test_Ownable2Step_PendingOwnerCannotActBeforeAccept() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        escrow.transferOwnership(newOwner);

        assertEq(escrow.owner(), owner);
        assertEq(escrow.pendingOwner(), newOwner);

        vm.prank(newOwner);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, newOwner)
        );
        escrow.setProtocolFee(200);
    }

    function test_Ownable2Step_OnlyPendingOwnerCanAccept() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        escrow.transferOwnership(newOwner);

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger)
        );
        escrow.acceptOwnership();

        assertEq(escrow.owner(), owner);
    }

    function test_Ownable_TransferOwnershipCannotBeHijacked() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger)
        );
        escrow.transferOwnership(newOwner);
    }

    function test_RenounceOwnership_DisablesAdminButNotEscrow() public {
        uint256 id = _createAndFundNative(_singleMilestone(1 ether));

        vm.prank(owner);
        escrow.renounceOwnership();
        assertEq(escrow.owner(), address(0));

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        escrow.pause();

        // Participants can still complete the agreement after ownership renouncement.
        vm.prank(buyer);
        escrow.approveMilestone(id);
        (,,,,,, NexusEscrow.AgreementStatus status,,,,) = escrow.agreements(id);
        assertEq(uint8(status), uint8(NexusEscrow.AgreementStatus.Completed));
    }

    // ---------------------------------------------------------------------
    // Pause is an availability lever only
    // ---------------------------------------------------------------------

    function test_Pause_BlocksAllAgreementPaths() public {
        uint256 id = _createAndFundNative(_singleMilestone(1 ether));

        vm.prank(owner);
        escrow.pause();

        vm.startPrank(buyer);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        escrow.createAgreement(seller, arbiter, address(0), _singleMilestone(1 ether), 0);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        escrow.fund{ value: 1 ether }(id);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        escrow.approveMilestone(id);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        escrow.raiseDispute(id);

        vm.expectRevert(Pausable.EnforcedPause.selector);
        escrow.cancelBeforeFunding(id);
        vm.stopPrank();

        vm.prank(arbiter);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        escrow.resolveDispute(id, 5000);
    }

    function test_Pause_DoesNotBlockFeeWithdrawalOrAdminConfig() public {
        uint256 id = _createAndFundNative(_singleMilestone(1 ether));
        vm.prank(buyer);
        escrow.approveMilestone(id);

        address rotated = makeAddr("newFeeRecipient");
        vm.startPrank(owner);
        escrow.pause();
        escrow.setProtocolFee(200);
        escrow.setFeeRecipient(rotated);
        vm.stopPrank();

        uint256 fee = escrow.accruedFees(address(0));
        uint256 before = rotated.balance;
        vm.prank(rotated);
        escrow.withdrawFees(address(0));
        assertEq(rotated.balance, before + fee);
    }

    function test_PauseDuringActive_UnpauseRestoresProgression() public {
        uint256 id = _createAndFundNative(_threeMilestones());
        vm.prank(buyer);
        escrow.approveMilestone(id); // 1/3

        vm.prank(owner);
        escrow.pause();

        vm.prank(buyer);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        escrow.approveMilestone(id);

        vm.prank(owner);
        escrow.unpause();

        vm.prank(buyer);
        escrow.approveMilestone(id);
        vm.prank(buyer);
        escrow.approveMilestone(id);

        (,,,,,, NexusEscrow.AgreementStatus status,,,,) = escrow.agreements(id);
        assertEq(uint8(status), uint8(NexusEscrow.AgreementStatus.Completed));
    }
}
