// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { NexEscrowCore } from "../src/NexEscrowCore.sol";
import { MockERC1271Wallet, MockRejectingWallet } from "./mocks/MockERC1271.sol";

/// @title NexEscrowCore — Demo 1 tranche A tests (signed bilateral intent)
/// @notice Covers whitepaper §18 invariants 7 (single activation), 8 (domain
///         separation) and 9 (EIP-1271 fail-closed), plus the EOA/smart-account signing
///         paths and the activation validations.
contract NexEscrowCoreTest is Test {
    NexEscrowCore internal core;

    uint256 internal constant BUYER_PK = 0xB0B;
    uint256 internal constant SELLER_PK = 0x5E11E8;
    uint256 internal constant OWNER_PK = 0xA11CE;

    address internal buyer;
    address internal seller;

    event AgreementActivated(
        uint256 indexed id,
        address indexed buyer,
        address indexed seller,
        bytes32 intentDigest,
        address settlementAsset,
        uint256 totalAmount,
        bytes32 milestonesHash
    );

    function setUp() public {
        core = new NexEscrowCore();
        buyer = vm.addr(BUYER_PK);
        seller = vm.addr(SELLER_PK);
    }

    // ── helpers ──────────────────────────────────────────────────────────

    function _intent() internal view returns (NexEscrowCore.AgreementIntent memory) {
        return NexEscrowCore.AgreementIntent({
            buyer: buyer,
            seller: seller,
            settlementAsset: address(0),
            totalAmount: 1 ether,
            milestonesHash: keccak256("milestones:0.5+0.5"),
            termsHash: keccak256("terms"),
            resolutionPolicyHash: keccak256("policy"),
            fundingDeadline: uint64(block.timestamp + 1 days),
            executionDeadline: uint64(block.timestamp + 7 days),
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

    // ── happy path ───────────────────────────────────────────────────────

    function test_Activate_BilateralEOA_Succeeds() public {
        NexEscrowCore.AgreementIntent memory intent = _intent();
        bytes32 digest = core.hashIntent(intent);

        vm.expectEmit(true, true, true, true);
        emit AgreementActivated(
            0, buyer, seller, digest, address(0), 1 ether, intent.milestonesHash
        );

        uint256 id = core.activate(intent, _sign(BUYER_PK, intent), _sign(SELLER_PK, intent));

        assertEq(id, 0);
        assertEq(core.nextAgreementId(), 1);
        assertTrue(core.isIntentConsumed(intent));
        (
            address b,
            address s,
            address asset,
            uint256 amount,
            bytes32 mh,,,,,
            NexEscrowCore.AgreementStatus status
        ) = core.agreements(id);
        assertEq(b, buyer);
        assertEq(s, seller);
        assertEq(asset, address(0));
        assertEq(amount, 1 ether);
        assertEq(mh, intent.milestonesHash);
        assertEq(uint8(status), uint8(NexEscrowCore.AgreementStatus.Activated));
    }

    // ── invariant 7: single activation ─────────────────────────────────────

    function test_Activate_RevertsOnReplay() public {
        NexEscrowCore.AgreementIntent memory intent = _intent();
        bytes memory bs = _sign(BUYER_PK, intent);
        bytes memory ss = _sign(SELLER_PK, intent);
        core.activate(intent, bs, ss);
        vm.expectRevert(NexEscrowCore.IntentAlreadyActivated.selector);
        core.activate(intent, bs, ss);
    }

    function test_Activate_DifferentNonce_NotReplay() public {
        NexEscrowCore.AgreementIntent memory a = _intent();
        core.activate(a, _sign(BUYER_PK, a), _sign(SELLER_PK, a));

        NexEscrowCore.AgreementIntent memory b = _intent();
        b.nonce = 2; // otherwise identical terms, a distinct intent
        uint256 id = core.activate(b, _sign(BUYER_PK, b), _sign(SELLER_PK, b));
        assertEq(id, 1);
    }

    // ── invariant 8: domain separation (verifying contract) ────────────────

    function test_Activate_RevertsOnForeignContractDomain() public {
        NexEscrowCore.AgreementIntent memory intent = _intent();
        // Signatures produced over THIS core's domain...
        bytes memory bs = _sign(BUYER_PK, intent);
        bytes memory ss = _sign(SELLER_PK, intent);
        // ...must not activate on a different deployment (different verifyingContract).
        NexEscrowCore other = new NexEscrowCore();
        assertTrue(core.domainSeparator() != other.domainSeparator());
        vm.expectRevert(NexEscrowCore.InvalidBuyerSignature.selector);
        other.activate(intent, bs, ss);
    }

    // ── invariant 9: EIP-1271 ──────────────────────────────────────────────

    function test_Activate_EIP1271_SmartAccountBuyer_Succeeds() public {
        MockERC1271Wallet wallet = new MockERC1271Wallet(vm.addr(OWNER_PK));
        NexEscrowCore.AgreementIntent memory intent = _intent();
        intent.buyer = address(wallet);

        // Wallet validates its owner's ECDSA signature over the digest.
        bytes memory buyerSig = _sign(OWNER_PK, intent);
        bytes memory sellerSig = _sign(SELLER_PK, intent);

        uint256 id = core.activate(intent, buyerSig, sellerSig);
        (address b,,,,,,,,,) = core.agreements(id);
        assertEq(b, address(wallet));
    }

    function test_Activate_EIP1271_FailClosed() public {
        MockRejectingWallet wallet = new MockRejectingWallet();
        NexEscrowCore.AgreementIntent memory intent = _intent();
        intent.buyer = address(wallet);

        // Even a well-formed ECDSA signature is rejected: the wallet returns a non-magic
        // value, so validation fails closed.
        bytes memory buyerSig = _sign(OWNER_PK, intent);
        bytes memory sellerSig = _sign(SELLER_PK, intent);

        vm.expectRevert(NexEscrowCore.InvalidBuyerSignature.selector);
        core.activate(intent, buyerSig, sellerSig);
    }

    // ── wrong signers ──────────────────────────────────────────────────────

    function test_Activate_RevertsWrongBuyerSigner() public {
        NexEscrowCore.AgreementIntent memory intent = _intent();
        // Precompute signatures: _sign() makes a staticcall to hashIntent, which must not
        // be the call vm.expectRevert intercepts.
        bytes memory wrongBuyerSig = _sign(SELLER_PK, intent);
        bytes memory sellerSig = _sign(SELLER_PK, intent);
        vm.expectRevert(NexEscrowCore.InvalidBuyerSignature.selector);
        core.activate(intent, wrongBuyerSig, sellerSig);
    }

    function test_Activate_RevertsWrongSellerSigner() public {
        NexEscrowCore.AgreementIntent memory intent = _intent();
        bytes memory buyerSig = _sign(BUYER_PK, intent);
        bytes memory wrongSellerSig = _sign(BUYER_PK, intent);
        vm.expectRevert(NexEscrowCore.InvalidSellerSignature.selector);
        core.activate(intent, buyerSig, wrongSellerSig);
    }

    // ── validations (checked before signatures) ────────────────────────────

    function test_Activate_RevertsZeroBuyer() public {
        NexEscrowCore.AgreementIntent memory intent = _intent();
        intent.buyer = address(0);
        vm.expectRevert(NexEscrowCore.ZeroBuyer.selector);
        core.activate(intent, "", "");
    }

    function test_Activate_RevertsIdenticalParties() public {
        NexEscrowCore.AgreementIntent memory intent = _intent();
        intent.seller = intent.buyer;
        vm.expectRevert(NexEscrowCore.IdenticalParties.selector);
        core.activate(intent, "", "");
    }

    function test_Activate_RevertsZeroAmount() public {
        NexEscrowCore.AgreementIntent memory intent = _intent();
        intent.totalAmount = 0;
        vm.expectRevert(NexEscrowCore.ZeroAmount.selector);
        core.activate(intent, "", "");
    }

    function test_Activate_RevertsEmptyMilestonesHash() public {
        NexEscrowCore.AgreementIntent memory intent = _intent();
        intent.milestonesHash = bytes32(0);
        vm.expectRevert(NexEscrowCore.EmptyMilestonesHash.selector);
        core.activate(intent, "", "");
    }

    function test_Activate_RevertsPastFundingDeadline() public {
        vm.warp(1_000_000);
        NexEscrowCore.AgreementIntent memory intent = _intent();
        intent.fundingDeadline = uint64(block.timestamp - 1);
        intent.executionDeadline = 0;
        vm.expectRevert(NexEscrowCore.InvalidDeadlines.selector);
        core.activate(intent, "", "");
    }

    function test_Activate_RevertsExecutionBeforeFunding() public {
        NexEscrowCore.AgreementIntent memory intent = _intent();
        intent.fundingDeadline = uint64(block.timestamp + 5 days);
        intent.executionDeadline = uint64(block.timestamp + 1 days);
        vm.expectRevert(NexEscrowCore.InvalidDeadlines.selector);
        core.activate(intent, "", "");
    }

    function test_HashIntent_IsContractBound() public view {
        // Sanity: the digest is a function of the domain, so it is non-zero and the
        // domain separator is bound to this contract address.
        assertTrue(core.hashIntent(_intent()) != bytes32(0));
        assertTrue(core.domainSeparator() != bytes32(0));
    }
}
