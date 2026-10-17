// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { TestBase } from "./utils/TestBase.t.sol";
import { NexusEscrow } from "../src/NexusEscrow.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { MockFalseReturnERC20 } from "./mocks/MockFalseReturnERC20.sol";
import { MockNoReturnERC20 } from "./mocks/MockNoReturnERC20.sol";
import { MockFeeOnTransferERC20 } from "./mocks/MockFeeOnTransferERC20.sol";
import { MockReentrantERC20 } from "./mocks/MockReentrantERC20.sol";
import { MockRejectingReceiver } from "./mocks/MockRejectingReceiver.sol";
import { MockDecimalsERC20 } from "./mocks/MockDecimalsERC20.sol";

contract NexusEscrowTokenEdgeTest is TestBase {
    // ---------------------------------------------------------------------
    // Broken / non-standard ERC-20 behaviours
    // ---------------------------------------------------------------------

    function test_Fund_RevertWhen_TokenReturnsFalse() public {
        MockFalseReturnERC20 falseToken = new MockFalseReturnERC20();
        falseToken.mint(buyer, 1 ether);

        uint256 id = _createAgreement(address(falseToken), _singleMilestone(1 ether), 0);

        vm.startPrank(buyer);
        falseToken.approve(address(escrow), 1 ether);
        vm.expectRevert(
            abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, address(falseToken))
        );
        escrow.fund(id);
        vm.stopPrank();

        (,,,,,, NexusEscrow.AgreementStatus status,,,,) = escrow.agreements(id);
        assertEq(uint8(status), uint8(NexusEscrow.AgreementStatus.AwaitingFunding));
        assertEq(falseToken.balanceOf(address(escrow)), 0);
    }

    function test_Fund_NoReturnToken_SucceedsAndPaysOut() public {
        MockNoReturnERC20 usdtLike = new MockNoReturnERC20();
        usdtLike.mint(buyer, 1_000_000);

        uint256 id = _createAgreement(address(usdtLike), _singleMilestone(1_000_000), 0);
        vm.startPrank(buyer);
        usdtLike.approve(address(escrow), 1_000_000);
        escrow.fund(id);
        vm.stopPrank();

        assertEq(usdtLike.balanceOf(address(escrow)), 1_000_000);

        vm.prank(buyer);
        escrow.approveMilestone(id);

        uint256 fee = escrow.accruedFees(address(usdtLike));
        assertEq(usdtLike.balanceOf(seller) + fee, 1_000_000);
    }

    function test_Fund_RevertWhen_FeeOnTransferToken() public {
        MockFeeOnTransferERC20 feeToken = new MockFeeOnTransferERC20();
        feeToken.mint(buyer, 1 ether);

        uint256 id = _createAgreement(address(feeToken), _singleMilestone(1 ether), 0);

        vm.startPrank(buyer);
        feeToken.approve(address(escrow), 1 ether);
        vm.expectRevert(NexusEscrow.UnsupportedTokenBehavior.selector);
        escrow.fund(id);
        vm.stopPrank();

        // Whole transaction reverted: agreement unfunded, nothing received.
        (,,,,,, NexusEscrow.AgreementStatus status,,,,) = escrow.agreements(id);
        assertEq(uint8(status), uint8(NexusEscrow.AgreementStatus.AwaitingFunding));
        assertEq(feeToken.balanceOf(address(escrow)), 0);
    }

    function test_Fund_RevertWhen_TokenIsNotAContract() public {
        address notAContract = makeAddr("notAContract");
        uint256 id = _createAgreement(notAContract, _singleMilestone(1 ether), 0);

        vm.prank(buyer);
        vm.expectRevert();
        escrow.fund(id);
    }

    // ---------------------------------------------------------------------
    // Malicious (reentrant) ERC-20
    // ---------------------------------------------------------------------

    function test_Fund_ReentrantToken_ReentryBlocked() public {
        MockReentrantERC20 evil = new MockReentrantERC20(escrow);
        evil.mint(buyer, 2 ether);

        // Agreement A is funded first and is the attack target.
        uint256 idA = _createAgreement(address(evil), _singleMilestone(1 ether), 0);
        vm.startPrank(buyer);
        evil.approve(address(escrow), 2 ether);
        escrow.fund(idA);
        vm.stopPrank();

        // Arming the token makes it reenter approveMilestone(A) during funding of B.
        evil.arm(idA);

        uint256 idB = _createAgreement(address(evil), _singleMilestone(1 ether), 0);
        vm.prank(buyer);
        escrow.fund(idB);

        assertTrue(evil.attackAttempted(), "attack hook did not fire");
        assertTrue(evil.reentryReverted(), "reentrant approveMilestone was not blocked");

        // Outer funding succeeded; the targeted milestone is untouched.
        (,,,,,, NexusEscrow.AgreementStatus statusB,,,,) = escrow.agreements(idB);
        assertEq(uint8(statusB), uint8(NexusEscrow.AgreementStatus.Active));
        NexusEscrow.Milestone memory m = escrow.getMilestone(idA, 0);
        assertEq(uint8(m.status), uint8(NexusEscrow.MilestoneStatus.Pending));
    }

    function test_ApproveMilestone_ReentrantToken_ReentryBlocked() public {
        MockReentrantERC20 evil = new MockReentrantERC20(escrow);
        evil.mint(buyer, 2 ether);

        uint256 idA = _createAgreement(address(evil), _singleMilestone(1 ether), 0);
        vm.startPrank(buyer);
        evil.approve(address(escrow), 2 ether);
        escrow.fund(idA);
        vm.stopPrank();

        // Arm, then release: the token reenters during its own payout transfer.
        evil.arm(idA);
        vm.prank(buyer);
        escrow.approveMilestone(idA);

        assertTrue(evil.attackAttempted(), "attack hook did not fire on payout");
        assertTrue(evil.reentryReverted(), "reentrant call from payout transfer was not blocked");

        NexusEscrow.Milestone memory m = escrow.getMilestone(idA, 0);
        assertEq(uint8(m.status), uint8(NexusEscrow.MilestoneStatus.Released));
    }

    // ---------------------------------------------------------------------
    // Arbitrary decimals
    // ---------------------------------------------------------------------

    function test_ArbitraryDecimals_Conservation() public {
        uint8[4] memory options = [0, 6, 8, 18];
        for (uint256 i = 0; i < options.length; ++i) {
            uint8 dec = options[i];
            MockDecimalsERC20 t = new MockDecimalsERC20(dec);
            t.mint(buyer, 1_000_000);

            uint256 id = _createAgreement(address(t), _singleMilestone(1_000_000), 0);
            vm.startPrank(buyer);
            t.approve(address(escrow), 1_000_000);
            escrow.fund(id);
            vm.stopPrank();

            vm.prank(buyer);
            escrow.approveMilestone(id);

            uint256 fee = escrow.accruedFees(address(t));
            assertEq(t.balanceOf(seller) + fee, 1_000_000, "conservation broken for decimals");
            assertEq(t.decimals(), dec);
        }
    }

    // ---------------------------------------------------------------------
    // Native payout failures
    // ---------------------------------------------------------------------

    function test_ApproveMilestone_RevertsWhen_SellerRejectsNative() public {
        MockRejectingReceiver rejector = new MockRejectingReceiver();
        vm.deal(buyer, 1 ether);

        vm.prank(buyer);
        uint256 id = escrow.createAgreement(
            address(rejector), arbiter, address(0), _singleMilestone(1 ether), 0
        );
        vm.prank(buyer);
        escrow.fund{ value: 1 ether }(id);

        vm.prank(buyer);
        vm.expectRevert(NexusEscrow.NativeTransferFailed.selector);
        escrow.approveMilestone(id);

        // Nothing changed and funds are still escrowed.
        NexusEscrow.Milestone memory m = escrow.getMilestone(id, 0);
        assertEq(uint8(m.status), uint8(NexusEscrow.MilestoneStatus.Pending));
        assertEq(address(escrow).balance, 1 ether);
    }

    function test_ResolveDispute_FullRefund_BypassesRejectingSeller() public {
        MockRejectingReceiver rejector = new MockRejectingReceiver();
        vm.deal(buyer, 1 ether);

        vm.prank(buyer);
        uint256 id = escrow.createAgreement(
            address(rejector), arbiter, address(0), _singleMilestone(1 ether), 0
        );
        vm.prank(buyer);
        escrow.fund{ value: 1 ether }(id);
        vm.prank(buyer);
        escrow.raiseDispute(id);

        uint256 buyerBefore = buyer.balance;
        vm.prank(arbiter);
        escrow.resolveDispute(id, 10_000); // 100% refund to buyer — seller never paid

        assertEq(buyer.balance, buyerBefore + 1 ether);
        assertEq(address(escrow).balance, 0);
    }

    function test_ResolveDispute_RevertsWhen_RejectingSellerIsDueFunds() public {
        MockRejectingReceiver rejector = new MockRejectingReceiver();
        vm.deal(buyer, 1 ether);

        vm.prank(buyer);
        uint256 id = escrow.createAgreement(
            address(rejector), arbiter, address(0), _singleMilestone(1 ether), 0
        );
        vm.prank(buyer);
        escrow.fund{ value: 1 ether }(id);
        vm.prank(buyer);
        escrow.raiseDispute(id);

        vm.prank(arbiter);
        vm.expectRevert(NexusEscrow.NativeTransferFailed.selector);
        escrow.resolveDispute(id, 5000); // seller share > 0 → payout to rejector reverts
    }

    // ---------------------------------------------------------------------
    // Dust / rounding
    // ---------------------------------------------------------------------

    function test_Rounding_DustIsConserved() public {
        uint128[] memory milestones = new uint128[](3);
        milestones[0] = 99; // fee rounds to 0
        milestones[1] = 9_999; // fee rounds to 99
        milestones[2] = 100_001; // fee rounds to 1_000
        uint256 total = _sum(milestones);

        vm.deal(buyer, total);
        uint256 id = _createNativeAgreement(milestones);
        vm.prank(buyer);
        escrow.fund{ value: total }(id);

        uint256 sellerBefore = seller.balance;
        uint256 feeBefore = escrow.accruedFees(address(0));
        for (uint256 i = 0; i < milestones.length; ++i) {
            vm.prank(buyer);
            escrow.approveMilestone(id);
        }

        uint256 fee = escrow.accruedFees(address(0)) - feeBefore;
        assertEq(seller.balance - sellerBefore + fee, total);
        assertEq(address(escrow).balance, fee);
    }

    function testFuzz_Rounding_NoWeiCreatedOrDestroyed(uint128 amount, uint16 feeBps) public {
        amount = uint128(bound(amount, 1, type(uint96).max));
        feeBps = uint16(bound(feeBps, 0, escrow.MAX_FEE_BPS()));
        vm.prank(owner);
        escrow.setProtocolFee(feeBps);

        vm.deal(buyer, amount);
        uint256 id = _createAndFundNative(_singleMilestone(amount));

        uint256 buyerBefore = buyer.balance;
        uint256 sellerBefore = seller.balance;

        vm.prank(buyer);
        escrow.raiseDispute(id);

        uint16 buyerBps = uint16(bound(uint256(keccak256(abi.encode(amount, feeBps))), 0, 10_000));
        vm.prank(arbiter);
        escrow.resolveDispute(id, buyerBps);

        uint256 refunded = buyer.balance - buyerBefore;
        uint256 paid = seller.balance - sellerBefore;
        uint256 fee = escrow.accruedFees(address(0));

        assertEq(refunded + paid + fee, amount, "value not conserved");
        assertEq(address(escrow).balance, fee, "escrow balance != accrued fees after completion");
    }
}
