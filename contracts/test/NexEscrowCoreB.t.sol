// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { NexEscrowCore } from "../src/NexEscrowCore.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockFeeOnTransferERC20 } from "./mocks/MockFeeOnTransferERC20.sol";
import { MockERC1271Wallet } from "./mocks/MockERC1271.sol";

/// @title NexEscrowCore — Demo 1 tranche B tests (funding + dispute liveness)
/// @notice Proves whitepaper §4 rules and §18 invariants 1-4: exact conservation
///         (principal_in == principal_out), the resolver never receives principal,
///         no disputed milestone is permanently non-finalizable, and the timeout split
///         is exactly the pre-signed `timeoutBuyerBps`. Pull payments mean a party that
///         cannot receive funds can never freeze settlement for the other.
contract NexEscrowCoreBTest is Test {
    NexEscrowCore internal core;

    uint256 internal constant BUYER_PK = 0xB0B;
    uint256 internal constant SELLER_PK = 0x5E11E8;
    uint256 internal constant WALLET_OWNER_PK = 0xA11CE;

    address internal buyer;
    address internal seller;
    address internal resolver = address(0xBEEF);
    address internal stranger = address(0xCAFE);
    address internal constant NATIVE = address(0);

    function setUp() public {
        core = new NexEscrowCore();
        buyer = vm.addr(BUYER_PK);
        seller = vm.addr(SELLER_PK);
        vm.deal(buyer, 1000 ether);
    }

    // ── builders ───────────────────────────────────────────────────────────

    function _policy() internal view returns (NexEscrowCore.ResolutionPolicy memory) {
        return NexEscrowCore.ResolutionPolicy({
            primaryResolver: resolver,
            appellateResolver: address(0),
            evidenceWindow: 1 days,
            rulingWindow: 3 days,
            appealWindow: 0,
            timeoutBuyerBps: 10_000, // default here: full buyer refund if the ruling lapses
            policyHash: keccak256("policy-doc")
        });
    }

    function _sum(uint128[] memory a) internal pure returns (uint256 s) {
        for (uint256 i; i < a.length; ++i) {
            s += a[i];
        }
    }

    function _intent(
        uint128[] memory amounts,
        NexEscrowCore.ResolutionPolicy memory policy,
        address asset,
        address b,
        address s
    ) internal view returns (NexEscrowCore.AgreementIntent memory) {
        return NexEscrowCore.AgreementIntent({
            buyer: b,
            seller: s,
            settlementAsset: asset,
            totalAmount: _sum(amounts),
            milestonesHash: core.hashMilestones(amounts),
            termsHash: keccak256("terms"),
            resolutionPolicyHash: core.hashPolicy(policy),
            fundingDeadline: uint64(block.timestamp + 1 days),
            executionDeadline: uint64(block.timestamp + 30 days),
            nonce: 1
        });
    }

    function _sign(uint256 pk, NexEscrowCore.AgreementIntent memory intent)
        internal
        view
        returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, core.hashIntent(intent));
        return abi.encodePacked(r, s, v);
    }

    function _activate(
        NexEscrowCore.AgreementIntent memory intent,
        uint256 buyerPk,
        uint256 sellerPk
    ) internal returns (uint256 id) {
        id = core.activate(intent, _sign(buyerPk, intent), _sign(sellerPk, intent));
    }

    /// @dev activate + fund a native-asset agreement with EOA buyer/seller.
    function _fundedNative(uint128[] memory amounts, NexEscrowCore.ResolutionPolicy memory policy)
        internal
        returns (uint256 id)
    {
        NexEscrowCore.AgreementIntent memory intent =
            _intent(amounts, policy, NATIVE, buyer, seller);
        id = _activate(intent, BUYER_PK, SELLER_PK);
        vm.prank(buyer);
        core.fund{ value: _sum(amounts) }(id, amounts, policy);
    }

    function _one(uint128 a) internal pure returns (uint128[] memory arr) {
        arr = new uint128[](1);
        arr[0] = a;
    }

    function _two(uint128 a, uint128 b) internal pure returns (uint128[] memory arr) {
        arr = new uint128[](2);
        arr[0] = a;
        arr[1] = b;
    }

    // ── funding ──────────────────────────────────────────────────────────────

    function test_Fund_Native_Succeeds() public {
        uint128[] memory amounts = _two(0.6 ether, 0.4 ether);
        uint256 id = _fundedNative(amounts, _policy());

        (,,, uint256 total,,,,,, NexEscrowCore.AgreementStatus status) = core.agreements(id);
        assertEq(total, 1 ether);
        assertEq(uint8(status), uint8(NexEscrowCore.AgreementStatus.Funded));
        assertEq(core.escrowedOf(id), 1 ether);
        assertEq(address(core).balance, 1 ether);
        assertEq(core.milestonesOf(id).length, 2);
    }

    function test_Fund_RevertsMilestonesHashMismatch() public {
        NexEscrowCore.ResolutionPolicy memory p = _policy();
        uint128[] memory committed = _two(0.6 ether, 0.4 ether);
        NexEscrowCore.AgreementIntent memory intent = _intent(committed, p, NATIVE, buyer, seller);
        uint256 id = _activate(intent, BUYER_PK, SELLER_PK);

        uint128[] memory wrong = _two(0.5 ether, 0.5 ether); // same sum, different schedule
        vm.prank(buyer);
        vm.expectRevert(NexEscrowCore.MilestonesHashMismatch.selector);
        core.fund{ value: 1 ether }(id, wrong, p);
    }

    function test_Fund_RevertsPolicyHashMismatch() public {
        NexEscrowCore.ResolutionPolicy memory p = _policy();
        uint128[] memory amounts = _one(1 ether);
        NexEscrowCore.AgreementIntent memory intent = _intent(amounts, p, NATIVE, buyer, seller);
        uint256 id = _activate(intent, BUYER_PK, SELLER_PK);

        NexEscrowCore.ResolutionPolicy memory tampered = p;
        tampered.timeoutBuyerBps = 0; // seller-favouring split not agreed by the signers
        vm.prank(buyer);
        vm.expectRevert(NexEscrowCore.PolicyHashMismatch.selector);
        core.fund{ value: 1 ether }(id, amounts, tampered);
    }

    function test_Fund_RevertsSumMismatch() public {
        NexEscrowCore.ResolutionPolicy memory p = _policy();
        uint128[] memory amounts = _one(1 ether);
        // Commit to a schedule summing 1 ether but declare totalAmount = 2 ether.
        NexEscrowCore.AgreementIntent memory intent = _intent(amounts, p, NATIVE, buyer, seller);
        intent.totalAmount = 2 ether;
        uint256 id = _activate(intent, BUYER_PK, SELLER_PK);
        vm.prank(buyer);
        vm.expectRevert(NexEscrowCore.MilestoneSumMismatch.selector);
        core.fund{ value: 1 ether }(id, amounts, p);
    }

    function test_Fund_RevertsAppealNotSupported() public {
        NexEscrowCore.ResolutionPolicy memory p = _policy();
        p.appealWindow = 1 days; // tranche C territory
        uint128[] memory amounts = _one(1 ether);
        NexEscrowCore.AgreementIntent memory intent = _intent(amounts, p, NATIVE, buyer, seller);
        uint256 id = _activate(intent, BUYER_PK, SELLER_PK);
        vm.prank(buyer);
        vm.expectRevert(NexEscrowCore.AppealNotSupportedYet.selector);
        core.fund{ value: 1 ether }(id, amounts, p);
    }

    function test_Fund_RevertsResolverIsParty() public {
        NexEscrowCore.ResolutionPolicy memory p = _policy();
        p.primaryResolver = buyer; // a party cannot be its own resolver
        uint128[] memory amounts = _one(1 ether);
        NexEscrowCore.AgreementIntent memory intent = _intent(amounts, p, NATIVE, buyer, seller);
        uint256 id = _activate(intent, BUYER_PK, SELLER_PK);
        vm.prank(buyer);
        vm.expectRevert(NexEscrowCore.InvalidPolicy.selector);
        core.fund{ value: 1 ether }(id, amounts, p);
    }

    function test_Fund_ERC20_Succeeds() public {
        MockERC20 token = new MockERC20("T", "T");
        token.mint(buyer, 1 ether);
        NexEscrowCore.ResolutionPolicy memory p = _policy();
        uint128[] memory amounts = _one(1 ether);
        NexEscrowCore.AgreementIntent memory intent =
            _intent(amounts, p, address(token), buyer, seller);
        uint256 id = _activate(intent, BUYER_PK, SELLER_PK);

        vm.startPrank(buyer);
        token.approve(address(core), 1 ether);
        core.fund(id, amounts, p);
        vm.stopPrank();

        assertEq(token.balanceOf(address(core)), 1 ether);
        assertEq(core.escrowedOf(id), 1 ether);
    }

    function test_Fund_ERC20_FeeOnTransfer_FailsClosed() public {
        MockFeeOnTransferERC20 token = new MockFeeOnTransferERC20();
        token.mint(buyer, 1 ether);
        NexEscrowCore.ResolutionPolicy memory p = _policy();
        uint128[] memory amounts = _one(1 ether);
        NexEscrowCore.AgreementIntent memory intent =
            _intent(amounts, p, address(token), buyer, seller);
        uint256 id = _activate(intent, BUYER_PK, SELLER_PK);

        vm.startPrank(buyer);
        token.approve(address(core), 1 ether);
        vm.expectRevert(NexEscrowCore.UnsupportedTokenBehavior.selector);
        core.fund(id, amounts, p);
        vm.stopPrank();
    }

    // ── happy path: in-order release ──────────────────────────────────────────

    function test_Approve_PaysSeller_InOrder_AndCompletes() public {
        uint128[] memory amounts = _two(0.6 ether, 0.4 ether);
        uint256 id = _fundedNative(amounts, _policy());

        vm.prank(buyer);
        core.approveMilestone(id, 0);
        assertEq(core.pendingWithdrawals(seller, NATIVE), 0.6 ether);
        assertEq(core.nextMilestoneOf(id), 1);

        vm.prank(buyer);
        core.approveMilestone(id, 1);
        assertEq(core.pendingWithdrawals(seller, NATIVE), 1 ether);

        (,,,,,,,,, NexEscrowCore.AgreementStatus status) = core.agreements(id);
        assertEq(uint8(status), uint8(NexEscrowCore.AgreementStatus.Completed));
        assertEq(core.escrowedOf(id), 0);

        // withdraw moves funds; conservation holds end-to-end.
        uint256 before = seller.balance;
        vm.prank(seller);
        core.withdraw(NATIVE);
        assertEq(seller.balance - before, 1 ether);
        assertEq(address(core).balance, 0);
    }

    function test_Approve_RevertsOutOfOrder() public {
        uint256 id = _fundedNative(_two(0.6 ether, 0.4 ether), _policy());
        vm.prank(buyer);
        vm.expectRevert(NexEscrowCore.WrongMilestone.selector);
        core.approveMilestone(id, 1);
    }

    function test_Approve_RevertsNotBuyer() public {
        uint256 id = _fundedNative(_one(1 ether), _policy());
        vm.prank(seller);
        vm.expectRevert(NexEscrowCore.NotBuyer.selector);
        core.approveMilestone(id, 0);
    }

    // ── dispute -> ruling ─────────────────────────────────────────────────────

    function test_Dispute_thenRule_SplitsAndCreditsPartiesOnly() public {
        uint256 id = _fundedNative(_one(1 ether), _policy());
        vm.prank(seller);
        core.disputeMilestone(id, 0);

        (uint256 evidenceDeadline,) = core.disputeDeadlines(id, 0);
        vm.warp(evidenceDeadline + 1); // into the ruling window

        vm.prank(resolver);
        core.rule(id, 0, 3000); // 30% buyer / 70% seller

        assertEq(core.pendingWithdrawals(buyer, NATIVE), 0.3 ether);
        assertEq(core.pendingWithdrawals(seller, NATIVE), 0.7 ether);
        assertEq(
            core.pendingWithdrawals(resolver, NATIVE), 0, "resolver must never receive principal"
        );
        assertEq(core.escrowedOf(id), 0);
    }

    function test_Rule_RevertsDuringEvidenceWindow() public {
        uint256 id = _fundedNative(_one(1 ether), _policy());
        vm.prank(buyer);
        core.disputeMilestone(id, 0);
        vm.prank(resolver);
        vm.expectRevert(NexEscrowCore.TooEarlyToRule.selector);
        core.rule(id, 0, 5000);
    }

    function test_Rule_RevertsAfterRulingWindow() public {
        uint256 id = _fundedNative(_one(1 ether), _policy());
        vm.prank(buyer);
        core.disputeMilestone(id, 0);
        (, uint256 rulingDeadline) = core.disputeDeadlines(id, 0);
        vm.warp(rulingDeadline + 1);
        vm.prank(resolver);
        vm.expectRevert(NexEscrowCore.RulingWindowClosed.selector);
        core.rule(id, 0, 5000);
    }

    function test_Rule_RevertsNotResolver() public {
        uint256 id = _fundedNative(_one(1 ether), _policy());
        vm.prank(buyer);
        core.disputeMilestone(id, 0);
        (uint256 e,) = core.disputeDeadlines(id, 0);
        vm.warp(e + 1);
        vm.prank(stranger);
        vm.expectRevert(NexEscrowCore.NotResolver.selector);
        core.rule(id, 0, 5000);
    }

    // ── timeout liveness (invariants 1,3,4) ────────────────────────────────────

    function test_FinalizeTimeout_AnyoneAfterDeadline_UsesCommittedSplit() public {
        NexEscrowCore.ResolutionPolicy memory p = _policy();
        p.timeoutBuyerBps = 10_000; // committed: full buyer refund
        uint256 id = _fundedNative(_one(1 ether), p);
        vm.prank(buyer);
        core.disputeMilestone(id, 0);

        (, uint256 rulingDeadline) = core.disputeDeadlines(id, 0);
        vm.warp(rulingDeadline + 1);

        // A completely unrelated account finalizes — liveness does not need a party.
        vm.prank(stranger);
        core.finalizeTimeout(id, 0);

        assertEq(
            core.pendingWithdrawals(buyer, NATIVE),
            1 ether,
            "timeout split must equal committed bps"
        );
        assertEq(core.pendingWithdrawals(seller, NATIVE), 0);
        assertEq(core.pendingWithdrawals(resolver, NATIVE), 0);
        assertEq(core.escrowedOf(id), 0);
    }

    function test_FinalizeTimeout_RevertsBeforeRulingDeadline() public {
        uint256 id = _fundedNative(_one(1 ether), _policy());
        vm.prank(buyer);
        core.disputeMilestone(id, 0);
        (uint256 e,) = core.disputeDeadlines(id, 0);
        vm.warp(e + 1); // still inside the ruling window
        vm.expectRevert(NexEscrowCore.NotTimeoutEligible.selector);
        core.finalizeTimeout(id, 0);
    }

    function test_Timeout_PartialSplit_MatchesCommitted() public {
        NexEscrowCore.ResolutionPolicy memory p = _policy();
        p.timeoutBuyerBps = 2500; // committed 25/75
        uint256 id = _fundedNative(_one(1 ether), p);
        vm.prank(seller);
        core.disputeMilestone(id, 0);
        (, uint256 rd) = core.disputeDeadlines(id, 0);
        vm.warp(rd + 1);
        core.finalizeTimeout(id, 0);
        assertEq(core.pendingWithdrawals(buyer, NATIVE), 0.25 ether);
        assertEq(core.pendingWithdrawals(seller, NATIVE), 0.75 ether);
    }

    // ── conservation across a mixed path (invariant 1) ─────────────────────────

    function test_Conservation_MixedPath() public {
        NexEscrowCore.ResolutionPolicy memory p = _policy();
        p.timeoutBuyerBps = 10_000;
        uint128[] memory amounts = new uint128[](3);
        amounts[0] = 0.5 ether;
        amounts[1] = 0.3 ether;
        amounts[2] = 0.2 ether;
        uint256 id = _fundedNative(amounts, p);

        // m0: approved -> seller 0.5
        vm.prank(buyer);
        core.approveMilestone(id, 0);
        // m1: disputed -> ruled 40/60 -> buyer 0.12, seller 0.18
        vm.prank(buyer);
        core.disputeMilestone(id, 1);
        (uint256 e,) = core.disputeDeadlines(id, 1);
        vm.warp(e + 1);
        vm.prank(resolver);
        core.rule(id, 1, 4000);
        // m2: disputed -> timeout (full buyer) -> buyer 0.2
        vm.prank(seller);
        core.disputeMilestone(id, 2);
        (, uint256 rd) = core.disputeDeadlines(id, 2);
        vm.warp(rd + 1);
        core.finalizeTimeout(id, 2);

        uint256 buyerPend = core.pendingWithdrawals(buyer, NATIVE);
        uint256 sellerPend = core.pendingWithdrawals(seller, NATIVE);
        assertEq(buyerPend + sellerPend, 1 ether, "principal_in == principal_out");
        assertEq(buyerPend, 0.32 ether);
        assertEq(sellerPend, 0.68 ether);
        assertEq(core.pendingWithdrawals(resolver, NATIVE), 0);
        assertEq(core.escrowedOf(id), 0);
        (,,,,,,,,, NexEscrowCore.AgreementStatus status) = core.agreements(id);
        assertEq(uint8(status), uint8(NexEscrowCore.AgreementStatus.Completed));
    }

    // ── pull-payment liveness: a non-receiving party cannot freeze settlement ──

    function test_PullPayment_NonReceivingSellerDoesNotFreeze() public {
        // Seller is a contract that can sign (EIP-1271) but has no receive/fallback,
        // so it cannot accept a native push. Settlement must still complete; only the
        // seller's own withdrawal is deferred.
        MockERC1271Wallet walletSeller = new MockERC1271Wallet(vm.addr(WALLET_OWNER_PK));
        NexEscrowCore.ResolutionPolicy memory p = _policy();
        uint128[] memory amounts = _one(1 ether);
        NexEscrowCore.AgreementIntent memory intent =
            _intent(amounts, p, NATIVE, buyer, address(walletSeller));
        uint256 id = _activate(intent, BUYER_PK, WALLET_OWNER_PK); // seller signs via its owner (1271)
        vm.prank(buyer);
        core.fund{ value: 1 ether }(id, amounts, p);

        // Settlement completes regardless of the seller being able to receive.
        vm.prank(buyer);
        core.approveMilestone(id, 0);
        (,,,,,,,,, NexEscrowCore.AgreementStatus status) = core.agreements(id);
        assertEq(uint8(status), uint8(NexEscrowCore.AgreementStatus.Completed));
        assertEq(core.pendingWithdrawals(address(walletSeller), NATIVE), 1 ether);

        // The seller's own withdrawal reverts (it cannot receive native) — but that is
        // isolated to the seller and never blocked the milestone.
        vm.prank(address(walletSeller));
        vm.expectRevert(NexEscrowCore.NativeTransferFailed.selector);
        core.withdraw(NATIVE);
    }

    function test_Withdraw_RevertsWhenNothing() public {
        vm.prank(stranger);
        vm.expectRevert(NexEscrowCore.NothingToWithdraw.selector);
        core.withdraw(NATIVE);
    }

    // ── fuzz: the split never creates or destroys a unit ───────────────────────

    function testFuzz_Rule_SplitConserves(uint16 bpsRaw) public {
        uint16 buyerBps = uint16(bound(bpsRaw, 0, 10_000));
        uint256 id = _fundedNative(_one(1 ether), _policy());
        vm.prank(buyer);
        core.disputeMilestone(id, 0);
        (uint256 e,) = core.disputeDeadlines(id, 0);
        vm.warp(e + 1);
        vm.prank(resolver);
        core.rule(id, 0, buyerBps);
        assertEq(
            core.pendingWithdrawals(buyer, NATIVE) + core.pendingWithdrawals(seller, NATIVE),
            1 ether
        );
        assertEq(core.pendingWithdrawals(resolver, NATIVE), 0);
    }
}
