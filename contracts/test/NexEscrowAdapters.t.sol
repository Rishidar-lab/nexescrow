// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { NexEscrowCore } from "../src/NexEscrowCore.sol";
import { AgreementMetadataAdapter } from "../src/adapters/AgreementMetadataAdapter.sol";
import { X402Adapter } from "../src/adapters/X402Adapter.sol";
import { AP2Adapter } from "../src/adapters/AP2Adapter.sol";
import { ERC8004Adapter } from "../src/adapters/ERC8004Adapter.sol";

/// @title NexEscrow Demo 1 tranche E tests (agent-interop adapters)
/// @notice Proves the adapters bind agent metadata to an agreement under party
///         authentication, and — invariant 10 — never move principal: all three adapters
///         touched leave the core's escrow, balance and pending payouts unchanged, and the
///         adapters hold no funds.
contract NexEscrowAdaptersTest is Test {
    NexEscrowCore internal core;
    X402Adapter internal x402;
    AP2Adapter internal ap2;
    ERC8004Adapter internal erc8004;

    uint256 internal constant BUYER_PK = 0xB0B;
    uint256 internal constant SELLER_PK = 0x5E11E8;
    address internal buyer;
    address internal seller;
    address internal resolver = address(0xBEEF);
    address internal stranger = address(0xCAFE);
    address internal constant NATIVE = address(0);

    uint256 internal id;

    event X402ResourceBound(
        uint256 indexed agreementId,
        uint256 indexed milestoneIndex,
        address indexed boundBy,
        bytes32 resourceHash,
        bytes32 paymentPayloadHash,
        string resourceURI
    );
    event AP2MandatesBound(
        uint256 indexed agreementId,
        uint256 indexed milestoneIndex,
        address indexed boundBy,
        bytes32 checkoutMandateHash,
        bytes32 paymentMandateHash,
        bytes32 receiptHash,
        string receiptURI
    );
    event AgentReferenceBound(
        uint256 indexed agreementId,
        address indexed boundBy,
        address agentRegistry,
        uint256 agentId,
        bytes32 validationRef
    );

    function setUp() public {
        core = new NexEscrowCore();
        x402 = new X402Adapter(address(core));
        ap2 = new AP2Adapter(address(core));
        erc8004 = new ERC8004Adapter(address(core));
        buyer = vm.addr(BUYER_PK);
        seller = vm.addr(SELLER_PK);
        vm.deal(buyer, 100 ether);
        id = _funded();
    }

    function _policy() internal view returns (NexEscrowCore.ResolutionPolicy memory) {
        return NexEscrowCore.ResolutionPolicy({
            primaryResolver: resolver,
            appellateResolver: address(0),
            evidenceWindow: 1 days,
            rulingWindow: 3 days,
            appealWindow: 0,
            timeoutBuyerBps: 10_000,
            policyHash: keccak256("policy")
        });
    }

    function _funded() internal returns (uint256 newId) {
        uint128[] memory amounts = new uint128[](1);
        amounts[0] = 1 ether;
        NexEscrowCore.AgreementIntent memory intent = NexEscrowCore.AgreementIntent({
            buyer: buyer,
            seller: seller,
            settlementAsset: NATIVE,
            totalAmount: 1 ether,
            milestonesHash: core.hashMilestones(amounts),
            termsHash: keccak256("terms"),
            resolutionPolicyHash: core.hashPolicy(_policy()),
            fundingDeadline: uint64(block.timestamp + 1 days),
            executionDeadline: uint64(block.timestamp + 30 days),
            nonce: 1
        });
        (uint8 vb, bytes32 rb, bytes32 sb) = vm.sign(BUYER_PK, core.hashIntent(intent));
        (uint8 vs, bytes32 rs, bytes32 ss) = vm.sign(SELLER_PK, core.hashIntent(intent));
        newId = core.activate(intent, abi.encodePacked(rb, sb, vb), abi.encodePacked(rs, ss, vs));
        vm.prank(buyer);
        core.fund{ value: 1 ether }(newId, amounts, _policy());
    }

    // ── x402 ───────────────────────────────────────────────────────────────

    function test_X402_BindAndRead() public {
        vm.expectEmit(true, true, true, true);
        emit X402ResourceBound(id, 0, buyer, keccak256("res"), keccak256("pay"), "https://api/x");
        vm.prank(buyer);
        x402.bindResource(id, 0, keccak256("res"), keccak256("pay"), "https://api/x");

        (bytes32 resourceHash, bytes32 paymentPayloadHash, bool set) = x402.bindings(id, 0);
        assertTrue(set);
        assertEq(resourceHash, keccak256("res"));
        assertEq(paymentPayloadHash, keccak256("pay"));
    }

    function test_X402_RevertsNonParty() public {
        vm.prank(stranger);
        vm.expectRevert(AgreementMetadataAdapter.NotParty.selector);
        x402.bindResource(id, 0, keccak256("res"), keccak256("pay"), "");
    }

    function test_X402_RevertsUnknownAgreement() public {
        vm.prank(buyer);
        vm.expectRevert(AgreementMetadataAdapter.UnknownAgreement.selector);
        x402.bindResource(999, 0, keccak256("res"), keccak256("pay"), "");
    }

    // ── AP2 ──────────────────────────────────────────────────────────────────

    function test_AP2_BindAndRead_BySeller() public {
        vm.expectEmit(true, true, true, true);
        emit AP2MandatesBound(
            id, 0, seller, keccak256("cart"), keccak256("pay"), keccak256("rcpt"), "ipfs://r"
        );
        vm.prank(seller);
        ap2.bindMandates(id, 0, keccak256("cart"), keccak256("pay"), keccak256("rcpt"), "ipfs://r");

        (bytes32 cart, bytes32 pay, bytes32 rcpt, bool set) = ap2.bindings(id, 0);
        assertTrue(set);
        assertEq(cart, keccak256("cart"));
        assertEq(pay, keccak256("pay"));
        assertEq(rcpt, keccak256("rcpt"));
    }

    function test_AP2_RevertsNonParty() public {
        vm.prank(stranger);
        vm.expectRevert(AgreementMetadataAdapter.NotParty.selector);
        ap2.bindMandates(id, 0, keccak256("cart"), keccak256("pay"), bytes32(0), "");
    }

    // ── ERC-8004 (experimental) ───────────────────────────────────────────────

    function test_ERC8004_BindAgentAndFeedback() public {
        address registry = address(0xA6E7);
        vm.expectEmit(true, true, false, true);
        emit AgentReferenceBound(id, buyer, registry, 42, keccak256("valid"));
        vm.prank(buyer);
        erc8004.bindAgent(id, registry, 42, keccak256("valid"));

        (address reg, uint256 agentId, bytes32 validationRef, bool set) = erc8004.agentRefs(id);
        assertTrue(set);
        assertEq(reg, registry);
        assertEq(agentId, 42);
        assertEq(validationRef, keccak256("valid"));

        // feedback (event-only) by the other party
        vm.prank(seller);
        erc8004.bindFeedback(id, 0, keccak256("fb"), keccak256("ev"));
    }

    function test_ERC8004_RevertsNonParty() public {
        vm.prank(stranger);
        vm.expectRevert(AgreementMetadataAdapter.NotParty.selector);
        erc8004.bindAgent(id, address(0xA6E7), 1, bytes32(0));
    }

    // ── invariant 10: adapters never move principal ───────────────────────────

    function test_Adapters_NeverMovePrincipal() public {
        uint256 escBefore = core.escrowedOf(id);
        uint256 coreBalBefore = address(core).balance;
        uint256 sellerPendBefore = core.pendingWithdrawals(seller, NATIVE);

        vm.startPrank(buyer);
        x402.bindResource(id, 0, keccak256("r"), keccak256("p"), "u");
        ap2.bindMandates(id, 0, keccak256("c"), keccak256("p"), keccak256("x"), "u");
        erc8004.bindAgent(id, address(0xA6E7), 7, keccak256("v"));
        erc8004.bindFeedback(id, 0, keccak256("fb"), keccak256("ev"));
        vm.stopPrank();

        // nothing about the core's money moved, and the adapters hold no funds
        assertEq(core.escrowedOf(id), escBefore);
        assertEq(address(core).balance, coreBalBefore);
        assertEq(core.pendingWithdrawals(seller, NATIVE), sellerPendBefore);
        assertEq(address(x402).balance, 0);
        assertEq(address(ap2).balance, 0);
        assertEq(address(erc8004).balance, 0);
    }

    function test_Adapter_RevertsZeroEscrow() public {
        vm.expectRevert(AgreementMetadataAdapter.ZeroEscrow.selector);
        new X402Adapter(address(0));
    }
}
