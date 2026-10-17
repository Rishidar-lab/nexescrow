// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { NexEscrowCore } from "../src/NexEscrowCore.sol";
import { QuorumResolver } from "../src/QuorumResolver.sol";

/// @title NexEscrowCore — Demo 1 tranche C tests (resolver modules, evidence, appeal)
/// @notice Proves the optional appellate path stays live (invariant 3) and per-milestone
///         isolated (invariant 5), that the resolver never receives principal (invariant 2),
///         and that a committed M-of-N QuorumResolver can deliver primary and appellate
///         rulings through the core's push boundary.
contract NexEscrowCoreCTest is Test {
    NexEscrowCore internal core;

    uint256 internal constant BUYER_PK = 0xB0B;
    uint256 internal constant SELLER_PK = 0x5E11E8;
    address internal buyer;
    address internal seller;
    address internal primary = address(0xA11);
    address internal appellate = address(0xB22);
    address internal stranger = address(0xCAFE);
    address internal constant NATIVE = address(0);

    uint40 internal constant EVIDENCE_WINDOW = 1 days;
    uint40 internal constant RULING_WINDOW = 3 days;
    uint40 internal constant APPEAL_WINDOW = 2 days;

    event EvidenceSubmitted(
        uint256 indexed id,
        uint256 indexed index,
        address indexed party,
        bytes32 evidenceHash,
        string evidenceURI
    );

    function setUp() public {
        core = new NexEscrowCore();
        buyer = vm.addr(BUYER_PK);
        seller = vm.addr(SELLER_PK);
        vm.deal(buyer, 1000 ether);
    }

    function _policy(address primary_, address appellate_, uint40 appealWindow_)
        internal
        pure
        returns (NexEscrowCore.ResolutionPolicy memory)
    {
        return NexEscrowCore.ResolutionPolicy({
            primaryResolver: primary_,
            appellateResolver: appellate_,
            evidenceWindow: EVIDENCE_WINDOW,
            rulingWindow: RULING_WINDOW,
            appealWindow: appealWindow_,
            timeoutBuyerBps: 10_000,
            policyHash: keccak256("policy")
        });
    }

    function _one(uint128 a) internal pure returns (uint128[] memory arr) {
        arr = new uint128[](1);
        arr[0] = a;
    }

    function _sign(uint256 pk, NexEscrowCore.AgreementIntent memory intent)
        internal
        view
        returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, core.hashIntent(intent));
        return abi.encodePacked(r, s, v);
    }

    function _funded(NexEscrowCore.ResolutionPolicy memory p) internal returns (uint256 id) {
        uint128[] memory amounts = _one(1 ether);
        NexEscrowCore.AgreementIntent memory intent = NexEscrowCore.AgreementIntent({
            buyer: buyer,
            seller: seller,
            settlementAsset: NATIVE,
            totalAmount: 1 ether,
            milestonesHash: core.hashMilestones(amounts),
            termsHash: keccak256("terms"),
            resolutionPolicyHash: core.hashPolicy(p),
            fundingDeadline: uint64(block.timestamp + 1 days),
            executionDeadline: uint64(block.timestamp + 60 days),
            nonce: 1
        });
        id = core.activate(intent, _sign(BUYER_PK, intent), _sign(SELLER_PK, intent));
        vm.prank(buyer);
        core.fund{ value: 1 ether }(id, amounts, p);
    }

    /// @dev dispute (by buyer) and warp into the ruling window; returns ruledAt baseline.
    function _disputeToRulingWindow(uint256 id) internal returns (uint256 nowTs) {
        vm.prank(buyer);
        core.disputeMilestone(id, 0);
        (uint256 evidenceDeadline,) = core.disputeDeadlines(id, 0);
        vm.warp(evidenceDeadline + 1);
        return block.timestamp;
    }

    // ── appeal path ────────────────────────────────────────────────────────

    function test_Rule_WithAppealWindow_DoesNotPayImmediately() public {
        uint256 id = _funded(_policy(primary, appellate, APPEAL_WINDOW));
        _disputeToRulingWindow(id);
        vm.prank(primary);
        core.rule(id, 0, 3000);
        // proposed, not settled: nothing credited, still escrowed, still disputed/funded.
        assertEq(core.pendingWithdrawals(buyer, NATIVE), 0);
        assertEq(core.pendingWithdrawals(seller, NATIVE), 0);
        assertEq(core.escrowedOf(id), 1 ether);
        (,,,,,,,,, NexEscrowCore.AgreementStatus status) = core.agreements(id);
        assertEq(uint8(status), uint8(NexEscrowCore.AgreementStatus.Funded));
    }

    function test_Appeal_thenFinalRule_AppellateOverrides() public {
        uint256 id = _funded(_policy(primary, appellate, APPEAL_WINDOW));
        _disputeToRulingWindow(id);
        vm.prank(primary);
        core.rule(id, 0, 3000); // primary proposes 30/70
        vm.prank(seller);
        core.appeal(id, 0);
        vm.prank(appellate);
        core.finalRule(id, 0, 7000); // appellate overrides to 70/30

        assertEq(core.pendingWithdrawals(buyer, NATIVE), 0.7 ether);
        assertEq(core.pendingWithdrawals(seller, NATIVE), 0.3 ether);
        assertEq(core.pendingWithdrawals(primary, NATIVE), 0);
        assertEq(core.pendingWithdrawals(appellate, NATIVE), 0);
        assertEq(core.escrowedOf(id), 0);
    }

    function test_NoAppeal_FinalizeRuling_PrimaryStands() public {
        uint256 id = _funded(_policy(primary, appellate, APPEAL_WINDOW));
        uint256 ruledAt = _disputeToRulingWindow(id);
        vm.prank(primary);
        core.rule(id, 0, 4000);
        vm.warp(ruledAt + APPEAL_WINDOW + 1); // appeal window lapses, no appeal
        vm.prank(stranger); // anyone
        core.finalizeRuling(id, 0);
        assertEq(core.pendingWithdrawals(buyer, NATIVE), 0.4 ether);
        assertEq(core.pendingWithdrawals(seller, NATIVE), 0.6 ether);
    }

    function test_AppealThenAppellateLapses_FinalizeRuling_PrimaryStands() public {
        uint256 id = _funded(_policy(primary, appellate, APPEAL_WINDOW));
        _disputeToRulingWindow(id);
        vm.prank(primary);
        core.rule(id, 0, 4000);
        vm.prank(buyer);
        core.appeal(id, 0);
        uint256 appealedAt = block.timestamp;
        vm.warp(appealedAt + RULING_WINDOW + 1); // appellate resolver lapsed
        vm.prank(stranger);
        core.finalizeRuling(id, 0); // primary ruling stands
        assertEq(core.pendingWithdrawals(buyer, NATIVE), 0.4 ether);
        assertEq(core.pendingWithdrawals(seller, NATIVE), 0.6 ether);
    }

    function test_FinalizeRuling_RevertsBeforeAppealWindowPasses() public {
        uint256 id = _funded(_policy(primary, appellate, APPEAL_WINDOW));
        _disputeToRulingWindow(id);
        vm.prank(primary);
        core.rule(id, 0, 4000);
        vm.expectRevert(NexEscrowCore.NotFinalizableYet.selector);
        core.finalizeRuling(id, 0);
    }

    function test_Appeal_RevertsAfterWindow() public {
        uint256 id = _funded(_policy(primary, appellate, APPEAL_WINDOW));
        uint256 ruledAt = _disputeToRulingWindow(id);
        vm.prank(primary);
        core.rule(id, 0, 4000);
        vm.warp(ruledAt + APPEAL_WINDOW + 1);
        vm.prank(buyer);
        vm.expectRevert(NexEscrowCore.AppealWindowClosed.selector);
        core.appeal(id, 0);
    }

    function test_Appeal_RevertsNoRuling() public {
        uint256 id = _funded(_policy(primary, appellate, APPEAL_WINDOW));
        _disputeToRulingWindow(id);
        vm.prank(buyer);
        vm.expectRevert(NexEscrowCore.NoRulingToAppeal.selector);
        core.appeal(id, 0);
    }

    function test_Appeal_RevertsNotParty() public {
        uint256 id = _funded(_policy(primary, appellate, APPEAL_WINDOW));
        _disputeToRulingWindow(id);
        vm.prank(primary);
        core.rule(id, 0, 4000);
        vm.prank(stranger);
        vm.expectRevert(NexEscrowCore.NotParty.selector);
        core.appeal(id, 0);
    }

    function test_FinalRule_RevertsNotAppealed() public {
        uint256 id = _funded(_policy(primary, appellate, APPEAL_WINDOW));
        _disputeToRulingWindow(id);
        vm.prank(primary);
        core.rule(id, 0, 4000);
        vm.prank(appellate);
        vm.expectRevert(NexEscrowCore.NotAppealed.selector);
        core.finalRule(id, 0, 7000);
    }

    function test_FinalRule_RevertsNotAppellate() public {
        uint256 id = _funded(_policy(primary, appellate, APPEAL_WINDOW));
        _disputeToRulingWindow(id);
        vm.prank(primary);
        core.rule(id, 0, 4000);
        vm.prank(buyer);
        core.appeal(id, 0);
        vm.prank(stranger);
        vm.expectRevert(NexEscrowCore.NotResolver.selector);
        core.finalRule(id, 0, 7000);
    }

    function test_FinalRule_RevertsAfterAppellateWindow() public {
        uint256 id = _funded(_policy(primary, appellate, APPEAL_WINDOW));
        _disputeToRulingWindow(id);
        vm.prank(primary);
        core.rule(id, 0, 4000);
        vm.prank(buyer);
        core.appeal(id, 0);
        uint256 appealedAt = block.timestamp;
        vm.warp(appealedAt + RULING_WINDOW + 1);
        vm.prank(appellate);
        vm.expectRevert(NexEscrowCore.RulingWindowClosed.selector);
        core.finalRule(id, 0, 7000);
    }

    function test_FinalizeTimeout_RevertsAfterRulingProposed() public {
        uint256 id = _funded(_policy(primary, appellate, APPEAL_WINDOW));
        _disputeToRulingWindow(id);
        vm.prank(primary);
        core.rule(id, 0, 4000);
        vm.warp(block.timestamp + 365 days);
        vm.expectRevert(NexEscrowCore.AlreadyRuled.selector);
        core.finalizeTimeout(id, 0);
    }

    function test_Rule_RevertsAlreadyRuled() public {
        uint256 id = _funded(_policy(primary, appellate, APPEAL_WINDOW));
        _disputeToRulingWindow(id);
        vm.prank(primary);
        core.rule(id, 0, 4000);
        vm.prank(primary);
        vm.expectRevert(NexEscrowCore.AlreadyRuled.selector);
        core.rule(id, 0, 5000);
    }

    function test_FinalizeTimeout_WhenResolverNeverRules_StillLive() public {
        uint256 id = _funded(_policy(primary, appellate, APPEAL_WINDOW));
        vm.prank(buyer);
        core.disputeMilestone(id, 0);
        (, uint256 rulingDeadline) = core.disputeDeadlines(id, 0);
        vm.warp(rulingDeadline + 1);
        vm.prank(stranger); // anyone — appeal policy does not remove the no-ruling timeout
        core.finalizeTimeout(id, 0);
        assertEq(core.pendingWithdrawals(buyer, NATIVE), 1 ether); // timeoutBuyerBps = 10000
    }

    // ── evidence ─────────────────────────────────────────────────────────────

    function test_SubmitEvidence_Emits() public {
        uint256 id = _funded(_policy(primary, appellate, APPEAL_WINDOW));
        vm.prank(buyer);
        core.disputeMilestone(id, 0);
        vm.expectEmit(true, true, true, true);
        emit EvidenceSubmitted(id, 0, buyer, keccak256("ev"), "ipfs://ev");
        vm.prank(buyer);
        core.submitEvidence(id, 0, keccak256("ev"), "ipfs://ev");
    }

    function test_SubmitEvidence_RevertsNotDisputed() public {
        uint256 id = _funded(_policy(primary, appellate, APPEAL_WINDOW));
        vm.prank(buyer);
        vm.expectRevert(NexEscrowCore.WrongMilestoneState.selector);
        core.submitEvidence(id, 0, keccak256("ev"), "");
    }

    function test_SubmitEvidence_RevertsNotParty() public {
        uint256 id = _funded(_policy(primary, appellate, APPEAL_WINDOW));
        vm.prank(buyer);
        core.disputeMilestone(id, 0);
        vm.prank(stranger);
        vm.expectRevert(NexEscrowCore.NotParty.selector);
        core.submitEvidence(id, 0, keccak256("ev"), "");
    }

    // ── policy validation for appeal ───────────────────────────────────────────

    function test_Fund_RevertsAppellateEqualsPrimary() public {
        _expectPolicyRevert(_policy(primary, primary, APPEAL_WINDOW));
    }

    function test_Fund_RevertsAppellateIsParty() public {
        _expectPolicyRevert(_policy(primary, buyer, APPEAL_WINDOW));
    }

    function test_Fund_RevertsAppealWindowZeroWithAppellate() public {
        _expectPolicyRevert(_policy(primary, appellate, 0));
    }

    function _expectPolicyRevert(NexEscrowCore.ResolutionPolicy memory p) internal {
        uint128[] memory amounts = _one(1 ether);
        NexEscrowCore.AgreementIntent memory intent = NexEscrowCore.AgreementIntent({
            buyer: buyer,
            seller: seller,
            settlementAsset: NATIVE,
            totalAmount: 1 ether,
            milestonesHash: core.hashMilestones(amounts),
            termsHash: keccak256("terms"),
            resolutionPolicyHash: core.hashPolicy(p),
            fundingDeadline: uint64(block.timestamp + 1 days),
            executionDeadline: uint64(block.timestamp + 60 days),
            nonce: 1
        });
        uint256 id = core.activate(intent, _sign(BUYER_PK, intent), _sign(SELLER_PK, intent));
        vm.prank(buyer);
        vm.expectRevert(NexEscrowCore.InvalidPolicy.selector);
        core.fund{ value: 1 ether }(id, amounts, p);
    }

    // ── QuorumResolver ─────────────────────────────────────────────────────────

    function _members() internal pure returns (uint256[] memory pks, address[] memory addrs) {
        pks = new uint256[](3);
        pks[0] = 0x1111;
        pks[1] = 0x2222;
        pks[2] = 0x3333;
        addrs = new address[](3);
        for (uint256 i; i < 3; ++i) {
            addrs[i] = vm.addr(pks[i]);
        }
    }

    /// @dev sign `digest` with each pk and return the signatures sorted by signer address
    ///      (QuorumResolver requires strictly-ascending signers).
    function _sortedSigs(uint256[] memory pks, bytes32 digest)
        internal
        pure
        returns (bytes[] memory sigs)
    {
        uint256 n = pks.length;
        // insertion sort pks by signer address
        for (uint256 i = 1; i < n; ++i) {
            uint256 key = pks[i];
            uint256 j = i;
            while (j > 0 && vm.addr(pks[j - 1]) > vm.addr(key)) {
                pks[j] = pks[j - 1];
                --j;
            }
            pks[j] = key;
        }
        sigs = new bytes[](n);
        for (uint256 i; i < n; ++i) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(pks[i], digest);
            sigs[i] = abi.encodePacked(r, s, v);
        }
    }

    function _two(uint256 a, uint256 b) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](2);
        arr[0] = a;
        arr[1] = b;
    }

    function test_Quorum_PrimaryRuling_2of3() public {
        (uint256[] memory pks, address[] memory addrs) = _members();
        QuorumResolver q = new QuorumResolver(address(core), addrs, 2);
        assertEq(q.core(), address(core));
        assertEq(q.resolverKind(), "QuorumResolver");

        uint256 id = _funded(_policy(address(q), address(0), 0)); // quorum as primary, no appeal
        _disputeToRulingWindow(id);

        bytes32 digest = q.hashRuling(id, 0, 2500, false);
        bytes[] memory sigs = _sortedSigs(_two(pks[0], pks[1]), digest);
        q.submitRuling(id, 0, 2500, sigs); // relayed by anyone

        assertEq(core.pendingWithdrawals(buyer, NATIVE), 0.25 ether);
        assertEq(core.pendingWithdrawals(seller, NATIVE), 0.75 ether);
        assertEq(core.pendingWithdrawals(address(q), NATIVE), 0);
    }

    function test_Quorum_RevertsBelowThreshold() public {
        (uint256[] memory pks, address[] memory addrs) = _members();
        QuorumResolver q = new QuorumResolver(address(core), addrs, 2);
        uint256 id = _funded(_policy(address(q), address(0), 0));
        _disputeToRulingWindow(id);
        bytes32 digest = q.hashRuling(id, 0, 2500, false);
        uint256[] memory one = new uint256[](1);
        one[0] = pks[0];
        bytes[] memory sigs = _sortedSigs(one, digest);
        vm.expectRevert(QuorumResolver.QuorumNotMet.selector);
        q.submitRuling(id, 0, 2500, sigs);
    }

    function test_Quorum_RevertsNonMember() public {
        (uint256[] memory pks, address[] memory addrs) = _members();
        QuorumResolver q = new QuorumResolver(address(core), addrs, 2);
        uint256 id = _funded(_policy(address(q), address(0), 0));
        _disputeToRulingWindow(id);
        bytes32 digest = q.hashRuling(id, 0, 2500, false);
        bytes[] memory sigs = _sortedSigs(_two(pks[0], 0x9999), digest); // 0x9999 not a member
        vm.expectRevert(QuorumResolver.SignerNotMember.selector);
        q.submitRuling(id, 0, 2500, sigs);
    }

    function test_Quorum_RevertsDuplicateSigner() public {
        (uint256[] memory pks, address[] memory addrs) = _members();
        QuorumResolver q = new QuorumResolver(address(core), addrs, 2);
        uint256 id = _funded(_policy(address(q), address(0), 0));
        _disputeToRulingWindow(id);
        bytes32 digest = q.hashRuling(id, 0, 2500, false);
        // same member twice (not sorted-ascending) -> rejected
        bytes[] memory sigs = _sortedSigs(_two(pks[0], pks[0]), digest);
        vm.expectRevert(QuorumResolver.UnsortedOrDuplicateSigners.selector);
        q.submitRuling(id, 0, 2500, sigs);
    }

    function test_Quorum_AsAppellate_FinalRuling() public {
        (uint256[] memory pks, address[] memory addrs) = _members();
        QuorumResolver q = new QuorumResolver(address(core), addrs, 2);
        // primary = EOA, appellate = quorum
        uint256 id = _funded(_policy(primary, address(q), APPEAL_WINDOW));
        _disputeToRulingWindow(id);
        vm.prank(primary);
        core.rule(id, 0, 3000);
        vm.prank(buyer);
        core.appeal(id, 0);

        bytes32 digest = q.hashRuling(id, 0, 8000, true);
        bytes[] memory sigs = _sortedSigs(_two(pks[1], pks[2]), digest);
        q.submitFinalRuling(id, 0, 8000, sigs);

        assertEq(core.pendingWithdrawals(buyer, NATIVE), 0.8 ether);
        assertEq(core.pendingWithdrawals(seller, NATIVE), 0.2 ether);
    }

    function test_Quorum_ConstructorValidations() public {
        (, address[] memory addrs) = _members();
        vm.expectRevert(QuorumResolver.BadThreshold.selector);
        new QuorumResolver(address(core), addrs, 0);
        vm.expectRevert(QuorumResolver.BadThreshold.selector);
        new QuorumResolver(address(core), addrs, 4); // > n
        address[] memory dup = new address[](2);
        dup[0] = addrs[0];
        dup[1] = addrs[0];
        vm.expectRevert(QuorumResolver.DuplicateMember.selector);
        new QuorumResolver(address(core), dup, 1);
        vm.expectRevert(QuorumResolver.ZeroCore.selector);
        new QuorumResolver(address(0), addrs, 2);
    }
}
