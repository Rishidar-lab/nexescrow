// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { TestBase } from "./utils/TestBase.t.sol";
import { NexusEscrow } from "../src/NexusEscrow.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

contract NexusEscrowAdminTest is TestBase {
    function test_Constructor_RevertWhen_ZeroFeeRecipient() public {
        vm.expectRevert(NexusEscrow.InvalidAddress.selector);
        new NexusEscrow(owner, address(0));
    }

    function test_SetProtocolFee_OnlyOwner() public {
        vm.prank(owner);
        escrow.setProtocolFee(250);
        assertEq(escrow.protocolFeeBps(), 250);
    }

    function test_SetProtocolFee_RevertWhen_NotOwner() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger)
        );
        escrow.setProtocolFee(250);
    }

    function test_SetProtocolFee_RevertWhen_TooHigh() public {
        uint16 tooHigh = escrow.MAX_FEE_BPS() + 1;
        vm.prank(owner);
        vm.expectRevert(NexusEscrow.FeeTooHigh.selector);
        escrow.setProtocolFee(tooHigh);
    }

    function test_SetProtocolFee_SnapshottedPerAgreement() public {
        uint256 id1 = _createNativeAgreement(_singleMilestone(1 ether));

        vm.prank(owner);
        escrow.setProtocolFee(500);

        uint256 id2 = _createNativeAgreement(_singleMilestone(1 ether));

        (,,,,, uint16 fee1,,,,,) = escrow.agreements(id1);
        (,,,,, uint16 fee2,,,,,) = escrow.agreements(id2);
        assertEq(fee1, 100); // default at time of creation
        assertEq(fee2, 500);
    }

    function test_SetFeeRecipient_OnlyOwner() public {
        address newRecipient = makeAddr("newRecipient");
        vm.prank(owner);
        escrow.setFeeRecipient(newRecipient);
        assertEq(escrow.feeRecipient(), newRecipient);
    }

    function test_SetFeeRecipient_RevertWhen_Zero() public {
        vm.prank(owner);
        vm.expectRevert(NexusEscrow.InvalidAddress.selector);
        escrow.setFeeRecipient(address(0));
    }

    function test_WithdrawFees_Native() public {
        uint256 id = _createAndFundNative(_singleMilestone(1 ether));
        vm.prank(buyer);
        escrow.approveMilestone(id);

        uint256 fee = escrow.accruedFees(address(0));
        assertGt(fee, 0);

        uint256 before = feeRecipient.balance;
        vm.prank(feeRecipient);
        escrow.withdrawFees(address(0));

        assertEq(feeRecipient.balance, before + fee);
        assertEq(escrow.accruedFees(address(0)), 0);
    }

    function test_WithdrawFees_ERC20() public {
        uint256 id = _createAndFundToken(_singleMilestone(1 ether));
        vm.prank(buyer);
        escrow.approveMilestone(id);

        uint256 fee = escrow.accruedFees(address(token));
        assertGt(fee, 0);

        vm.prank(feeRecipient);
        escrow.withdrawFees(address(token));

        assertEq(token.balanceOf(feeRecipient), fee);
        assertEq(escrow.accruedFees(address(token)), 0);
    }

    function test_WithdrawFees_RevertWhen_NotFeeRecipient() public {
        vm.prank(stranger);
        vm.expectRevert(NexusEscrow.NotAuthorized.selector);
        escrow.withdrawFees(address(0));
    }

    function test_WithdrawFees_RevertWhen_Nothing() public {
        vm.prank(feeRecipient);
        vm.expectRevert(NexusEscrow.NothingToWithdraw.selector);
        escrow.withdrawFees(address(0));
    }

    function test_Pause_BlocksCreateFundApprove() public {
        uint256 id = _createAndFundNative(_singleMilestone(1 ether));

        vm.prank(owner);
        escrow.pause();

        vm.prank(buyer);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        escrow.createAgreement(seller, arbiter, address(0), _singleMilestone(1 ether), 0);

        vm.prank(buyer);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        escrow.approveMilestone(id);
    }

    function test_Unpause_RestoresOperation() public {
        vm.startPrank(owner);
        escrow.pause();
        escrow.unpause();
        vm.stopPrank();

        // should not revert
        _createNativeAgreement(_singleMilestone(1 ether));
    }

    function test_Pause_OnlyOwner() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger)
        );
        escrow.pause();
    }

    function test_OwnershipTransfer_TwoStep() public {
        address newOwner = makeAddr("newOwner");

        vm.prank(owner);
        escrow.transferOwnership(newOwner);

        // not yet transferred
        assertEq(escrow.owner(), owner);

        vm.prank(newOwner);
        escrow.acceptOwnership();

        assertEq(escrow.owner(), newOwner);
    }

    // ---------------------------------------------------------------------
    // Fee configuration edge cases
    // ---------------------------------------------------------------------

    function test_SetProtocolFee_CapBoundary_ExactCapAllowed() public {
        uint16 cap = escrow.MAX_FEE_BPS();
        vm.prank(owner);
        escrow.setProtocolFee(cap);
        assertEq(escrow.protocolFeeBps(), 1_000);
    }

    function test_SetProtocolFee_NoBypassAboveCap() public {
        vm.prank(owner);
        vm.expectRevert(NexusEscrow.FeeTooHigh.selector);
        escrow.setProtocolFee(1_001);

        vm.prank(owner);
        vm.expectRevert(NexusEscrow.FeeTooHigh.selector);
        escrow.setProtocolFee(type(uint16).max);

        assertEq(escrow.protocolFeeBps(), 100);
    }

    function test_SetProtocolFee_DuringActiveAgreement_DoesNotAffectInFlight() public {
        uint128[] memory milestones = _threeMilestones();
        uint256 id = _createAndFundNative(milestones);

        vm.prank(buyer);
        escrow.approveMilestone(id); // M0 at 1% (default)

        vm.prank(owner);
        escrow.setProtocolFee(900); // raise mid-agreement

        (,,,,, uint16 storedFee,,,,,) = escrow.agreements(id);
        assertEq(storedFee, 100, "in-flight fee mutated");

        uint256 sellerBefore = seller.balance;
        vm.prank(buyer);
        escrow.approveMilestone(id); // M1 must still pay 1% fee

        uint256 expectedFee = (uint256(milestones[1]) * 100) / 10_000;
        assertEq(seller.balance - sellerBefore, milestones[1] - expectedFee);

        // A new agreement picks up the new fee.
        uint256 newId = _createNativeAgreement(_singleMilestone(1 ether));
        (,,,,, uint16 newFee,,,,,) = escrow.agreements(newId);
        assertEq(newFee, 900);
    }

    function test_SetFeeRecipient_AccruedFeesFollowCurrentRecipient() public {
        uint256 id = _createAndFundNative(_singleMilestone(1 ether));
        vm.prank(buyer);
        escrow.approveMilestone(id);

        uint256 accrued = escrow.accruedFees(address(0));
        address rotated = makeAddr("rotatedRecipient");

        vm.prank(owner);
        escrow.setFeeRecipient(rotated);

        uint256 before = rotated.balance;
        vm.prank(rotated);
        escrow.withdrawFees(address(0));
        assertEq(rotated.balance, before + accrued);
    }

    function test_WithdrawFees_WorksWhilePaused() public {
        uint256 id = _createAndFundNative(_singleMilestone(1 ether));
        vm.prank(buyer);
        escrow.approveMilestone(id);

        vm.prank(owner);
        escrow.pause();

        uint256 fee = escrow.accruedFees(address(0));
        uint256 before = feeRecipient.balance;
        vm.prank(feeRecipient);
        escrow.withdrawFees(address(0));
        assertEq(feeRecipient.balance, before + fee);
    }

    function test_WithdrawFees_TwiceRevertsSecondTime() public {
        uint256 id = _createAndFundNative(_singleMilestone(1 ether));
        vm.prank(buyer);
        escrow.approveMilestone(id);

        vm.prank(feeRecipient);
        escrow.withdrawFees(address(0));

        vm.prank(feeRecipient);
        vm.expectRevert(NexusEscrow.NothingToWithdraw.selector);
        escrow.withdrawFees(address(0));
    }
}
