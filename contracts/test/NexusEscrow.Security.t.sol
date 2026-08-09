// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { TestBase } from "./utils/TestBase.t.sol";
import { ReentrantBuyer } from "./mocks/ReentrantBuyer.sol";

contract NexusEscrowSecurityTest is TestBase {
    function test_Reentrancy_BlockedAcrossFunctions() public {
        ReentrantBuyer attacker = new ReentrantBuyer(escrow);
        vm.deal(address(attacker), 1 ether);

        vm.prank(address(attacker));
        attacker.createAgreement(seller, arbiter, address(0), _singleMilestone(1 ether), 0);

        vm.prank(address(attacker));
        attacker.fund(1 ether);

        vm.prank(address(attacker));
        attacker.raiseDispute();

        // Arbiter refunds 100% to buyer (the attacker contract), triggering its
        // receive() hook mid-call, which tries to reenter approveMilestone().
        uint256 id = attacker.agreementId();
        vm.prank(arbiter);
        escrow.resolveDispute(id, 10_000);

        assertTrue(attacker.attacked(), "attacker receive() hook did not fire");
        assertTrue(attacker.reentrancyReverted(), "reentrant call should have reverted");

        // Despite the blocked reentrant call, the outer resolveDispute must have
        // completed successfully and paid out correctly.
        assertEq(address(attacker).balance, 1 ether);
    }

    /// @notice Milestone amounts always sum to the stored total, for any valid input set.
    function testFuzz_MilestoneSumMatchesTotal(uint8 count, uint128 seed) public {
        count = uint8(bound(count, 1, escrow.MAX_MILESTONES()));
        uint128[] memory milestones = new uint128[](count);

        uint256 expectedTotal;
        for (uint256 i = 0; i < count; ++i) {
            // Keep individual amounts small enough that the sum can't overflow uint128.
            uint128 amount =
                uint128(bound(uint256(keccak256(abi.encode(seed, i))), 1, 1_000_000 ether));
            milestones[i] = amount;
            expectedTotal += amount;
        }
        vm.assume(expectedTotal <= type(uint128).max);

        uint256 id = _createNativeAgreement(milestones);
        (,,,, uint128 totalAmount,,,,,,) = escrow.agreements(id);
        assertEq(totalAmount, expectedTotal);
    }

    /// @notice The fee charged on a release never exceeds the milestone amount, and
    ///         seller + fee always reconstitute the full milestone amount.
    function testFuzz_FeeNeverExceedsAmount(uint128 amount, uint16 feeBps) public {
        amount = uint128(bound(amount, 1, 1_000_000 ether));
        feeBps = uint16(bound(feeBps, 0, escrow.MAX_FEE_BPS()));

        vm.prank(owner);
        escrow.setProtocolFee(feeBps);

        vm.deal(buyer, amount);
        uint256 id = _createAndFundNative(_singleMilestone(amount));
        uint256 sellerBefore = seller.balance;

        vm.prank(buyer);
        escrow.approveMilestone(id);

        uint256 fee = escrow.accruedFees(address(0));
        uint256 sellerReceived = seller.balance - sellerBefore;

        assertLe(fee, amount);
        assertEq(sellerReceived + fee, amount);
    }

    /// @notice Dispute splits always conserve the milestone amount across buyer, seller, and fee.
    function testFuzz_DisputeSplitConservesAmount(uint128 amount, uint16 buyerBps) public {
        amount = uint128(bound(amount, 1, 1_000_000 ether));
        buyerBps = uint16(bound(buyerBps, 0, escrow.BPS_DENOMINATOR()));

        vm.deal(buyer, amount);
        uint256 id = _createAndFundNative(_singleMilestone(amount));
        vm.prank(buyer);
        escrow.raiseDispute(id);

        uint256 buyerBefore = buyer.balance;
        uint256 sellerBefore = seller.balance;

        vm.prank(arbiter);
        escrow.resolveDispute(id, buyerBps);

        uint256 buyerReceived = buyer.balance - buyerBefore;
        uint256 sellerReceived = seller.balance - sellerBefore;
        uint256 fee = escrow.accruedFees(address(0));

        assertEq(buyerReceived + sellerReceived + fee, amount);
    }
}
