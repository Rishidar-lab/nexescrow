// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { NexEscrowCore } from "../src/NexEscrowCore.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";
import { MockERC1271Wallet } from "./mocks/MockERC1271.sol";
import {
    MockMigrationReceiver,
    RejectingMigrationReceiver,
    RevertingMigrationReceiver
} from "./mocks/MockMigrationReceiver.sol";

/// @title NexEscrowCore — Demo 1 tranche D tests (user-consented migration)
/// @notice Proves whitepaper §9: migration is bilateral (both EIP-712 signatures), atomic
///         (principal arrives at the destination or the tx reverts), preserves parties /
///         asset / remaining principal / unsettled milestones (invariant 6), is blocked over
///         an active dispute, and has no admin sweep. Signatures bind the destination and
///         the exact remaining state, so a stale authorization cannot be reused.
contract NexEscrowCoreDTest is Test {
    NexEscrowCore internal core;

    uint256 internal constant BUYER_PK = 0xB0B;
    uint256 internal constant SELLER_PK = 0x5E11E8;
    uint256 internal constant OWNER_PK = 0xA11CE;
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

    function _sum(uint128[] memory a) internal pure returns (uint256 s) {
        for (uint256 i; i < a.length; ++i) {
            s += a[i];
        }
    }

    function _three(uint128 a, uint128 b, uint128 c) internal pure returns (uint128[] memory arr) {
        arr = new uint128[](3);
        arr[0] = a;
        arr[1] = b;
        arr[2] = c;
    }

    function _sign(uint256 pk, NexEscrowCore.AgreementIntent memory intent)
        internal
        view
        returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, core.hashIntent(intent));
        return abi.encodePacked(r, s, v);
    }

    function _intent(uint128[] memory amounts, address asset, address b, address s)
        internal
        view
        returns (NexEscrowCore.AgreementIntent memory)
    {
        return NexEscrowCore.AgreementIntent({
            buyer: b,
            seller: s,
            settlementAsset: asset,
            totalAmount: _sum(amounts),
            milestonesHash: core.hashMilestones(amounts),
            termsHash: keccak256("terms"),
            resolutionPolicyHash: core.hashPolicy(_policy()),
            fundingDeadline: uint64(block.timestamp + 1 days),
            executionDeadline: uint64(block.timestamp + 60 days),
            nonce: 1
        });
    }

    function _fundedNative(uint128[] memory amounts) internal returns (uint256 id) {
        NexEscrowCore.AgreementIntent memory intent = _intent(amounts, NATIVE, buyer, seller);
        id = core.activate(intent, _sign(BUYER_PK, intent), _sign(SELLER_PK, intent));
        vm.prank(buyer);
        core.fund{ value: _sum(amounts) }(id, amounts, _policy());
    }

    function _signMig(uint256 pk, uint256 id, address target) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, core.hashMigration(id, target));
        return abi.encodePacked(r, s, v);
    }

    // ── core migration ─────────────────────────────────────────────────────

    function test_Migrate_MovesRemainingPrincipalAndState() public {
        uint256 id = _fundedNative(_three(0.5 ether, 0.3 ether, 0.2 ether));
        vm.prank(buyer);
        core.approveMilestone(id, 0); // seller credited 0.5; remaining escrow 0.5

        MockMigrationReceiver target = new MockMigrationReceiver();
        core.migrate(
            id,
            address(target),
            _signMig(BUYER_PK, id, address(target)),
            _signMig(SELLER_PK, id, address(target))
        );

        // destination received the preserved state + the exact remaining principal
        assertEq(target.legacyId(), id);
        assertEq(target.rcvBuyer(), buyer);
        assertEq(target.rcvSeller(), seller);
        assertEq(target.rcvAsset(), NATIVE);
        assertEq(target.rcvPrincipal(), 0.5 ether);
        assertEq(target.rcvValue(), 0.5 ether);
        assertEq(address(target).balance, 0.5 ether);
        uint128[] memory got = target.rcvMilestones();
        assertEq(got.length, 2);
        assertEq(got[0], 0.3 ether);
        assertEq(got[1], 0.2 ether);

        // source is drained of escrow and terminally Migrated
        assertEq(core.escrowedOf(id), 0);
        (,,,,,,,,, NexEscrowCore.AgreementStatus status) = core.agreements(id);
        assertEq(uint8(status), uint8(NexEscrowCore.AgreementStatus.Migrated));

        // conservation: 1.0 = 0.5 settled to seller (still withdrawable) + 0.5 migrated out
        assertEq(core.pendingWithdrawals(seller, NATIVE), 0.5 ether);
        assertEq(address(core).balance, 0.5 ether);
    }

    function test_Migrate_RequiresBothSignatures() public {
        uint256 id = _fundedNative(_three(0.5 ether, 0.3 ether, 0.2 ether));
        MockMigrationReceiver target = new MockMigrationReceiver();
        bytes memory buyerSig = _signMig(BUYER_PK, id, address(target));
        bytes memory badSellerSig = _signMig(BUYER_PK, id, address(target)); // buyer signs as seller
        vm.expectRevert(NexEscrowCore.InvalidSellerSignature.selector);
        core.migrate(id, address(target), buyerSig, badSellerSig);
    }

    function test_Migrate_StateBindingInvalidatesStaleSignatures() public {
        uint256 id = _fundedNative(_three(0.5 ether, 0.3 ether, 0.2 ether));
        MockMigrationReceiver target = new MockMigrationReceiver();
        // Authorize at the current (unapproved) state.
        bytes memory buyerSig = _signMig(BUYER_PK, id, address(target));
        bytes memory sellerSig = _signMig(SELLER_PK, id, address(target));
        // State moves: approving m0 changes remaining principal + fromMilestone.
        vm.prank(buyer);
        core.approveMilestone(id, 0);
        // The stale signatures no longer match the recomputed digest.
        vm.expectRevert(NexEscrowCore.InvalidBuyerSignature.selector);
        core.migrate(id, address(target), buyerSig, sellerSig);
    }

    function test_Migrate_TargetAddressBinding() public {
        uint256 id = _fundedNative(_three(0.5 ether, 0.3 ether, 0.2 ether));
        MockMigrationReceiver t1 = new MockMigrationReceiver();
        MockMigrationReceiver t2 = new MockMigrationReceiver();
        // Signed for t1 ...
        bytes memory buyerSig = _signMig(BUYER_PK, id, address(t1));
        bytes memory sellerSig = _signMig(SELLER_PK, id, address(t1));
        // ... cannot authorize migration to t2.
        vm.expectRevert(NexEscrowCore.InvalidBuyerSignature.selector);
        core.migrate(id, address(t2), buyerSig, sellerSig);
    }

    function test_Migrate_RevertsActiveDispute() public {
        uint256 id = _fundedNative(_three(0.5 ether, 0.3 ether, 0.2 ether));
        vm.prank(buyer);
        core.disputeMilestone(id, 0);
        MockMigrationReceiver target = new MockMigrationReceiver();
        bytes memory bs = _signMig(BUYER_PK, id, address(target));
        bytes memory ss = _signMig(SELLER_PK, id, address(target));
        vm.expectRevert(NexEscrowCore.MigrationActiveDispute.selector);
        core.migrate(id, address(target), bs, ss);
    }

    function test_Migrate_RejectingTarget_FailsClosed() public {
        uint256 id = _fundedNative(_three(0.5 ether, 0.3 ether, 0.2 ether));
        RejectingMigrationReceiver target = new RejectingMigrationReceiver();
        bytes memory bs = _signMig(BUYER_PK, id, address(target));
        bytes memory ss = _signMig(SELLER_PK, id, address(target));
        vm.expectRevert(NexEscrowCore.MigrationRejected.selector);
        core.migrate(id, address(target), bs, ss);
        // atomic: nothing moved, agreement still Funded
        assertEq(core.escrowedOf(id), 1 ether);
        assertEq(address(core).balance, 1 ether);
        (,,,,,,,,, NexEscrowCore.AgreementStatus status) = core.agreements(id);
        assertEq(uint8(status), uint8(NexEscrowCore.AgreementStatus.Funded));
    }

    function test_Migrate_RevertingTarget_Atomic() public {
        uint256 id = _fundedNative(_three(0.5 ether, 0.3 ether, 0.2 ether));
        RevertingMigrationReceiver target = new RevertingMigrationReceiver();
        bytes memory bs = _signMig(BUYER_PK, id, address(target));
        bytes memory ss = _signMig(SELLER_PK, id, address(target));
        vm.expectRevert(RevertingMigrationReceiver.Nope.selector);
        core.migrate(id, address(target), bs, ss);
        assertEq(core.escrowedOf(id), 1 ether);
    }

    function test_Migrate_ERC20() public {
        MockERC20 token = new MockERC20("T", "T");
        token.mint(buyer, 1 ether);
        uint128[] memory amounts = _three(0.5 ether, 0.3 ether, 0.2 ether);
        NexEscrowCore.AgreementIntent memory intent =
            _intent(amounts, address(token), buyer, seller);
        uint256 id = core.activate(intent, _sign(BUYER_PK, intent), _sign(SELLER_PK, intent));
        vm.startPrank(buyer);
        token.approve(address(core), 1 ether);
        core.fund(id, amounts, _policy());
        vm.stopPrank();

        MockMigrationReceiver target = new MockMigrationReceiver();
        core.migrate(
            id,
            address(target),
            _signMig(BUYER_PK, id, address(target)),
            _signMig(SELLER_PK, id, address(target))
        );
        assertEq(token.balanceOf(address(target)), 1 ether);
        assertEq(target.rcvPrincipal(), 1 ether);
        assertEq(target.rcvValue(), 0); // no native for an ERC-20 migration
        assertEq(token.balanceOf(address(core)), 0);
    }

    function test_Migrate_RevertsNotFunded() public {
        // Activated but not funded.
        uint128[] memory amounts = _three(0.5 ether, 0.3 ether, 0.2 ether);
        NexEscrowCore.AgreementIntent memory intent = _intent(amounts, NATIVE, buyer, seller);
        uint256 id = core.activate(intent, _sign(BUYER_PK, intent), _sign(SELLER_PK, intent));
        MockMigrationReceiver target = new MockMigrationReceiver();
        bytes memory bs = _signMig(BUYER_PK, id, address(target));
        bytes memory ss = _signMig(SELLER_PK, id, address(target));
        vm.expectRevert(NexEscrowCore.NotFunded.selector);
        core.migrate(id, address(target), bs, ss);
    }

    function test_Migrate_RevertsZeroAndSelfTarget() public {
        uint256 id = _fundedNative(_three(0.5 ether, 0.3 ether, 0.2 ether));
        vm.expectRevert(NexEscrowCore.ZeroTarget.selector);
        core.migrate(id, address(0), "", "");
        vm.expectRevert(NexEscrowCore.SelfTarget.selector);
        core.migrate(id, address(core), "", "");
    }

    function test_Migrate_EIP1271SellerParty() public {
        MockERC1271Wallet walletSeller = new MockERC1271Wallet(vm.addr(OWNER_PK));
        uint128[] memory amounts = _three(0.5 ether, 0.3 ether, 0.2 ether);
        NexEscrowCore.AgreementIntent memory intent =
            _intent(amounts, NATIVE, buyer, address(walletSeller));
        uint256 id = core.activate(intent, _sign(BUYER_PK, intent), _sign(OWNER_PK, intent));
        vm.prank(buyer);
        core.fund{ value: 1 ether }(id, amounts, _policy());

        MockMigrationReceiver target = new MockMigrationReceiver();
        // seller authorizes migration through its EIP-1271 owner key
        core.migrate(
            id,
            address(target),
            _signMig(BUYER_PK, id, address(target)),
            _signMig(OWNER_PK, id, address(target))
        );
        assertEq(target.rcvSeller(), address(walletSeller));
        assertEq(target.rcvPrincipal(), 1 ether);
    }

    function test_Migrate_LegacyFrozenAfter() public {
        uint256 id = _fundedNative(_three(0.5 ether, 0.3 ether, 0.2 ether));
        MockMigrationReceiver target = new MockMigrationReceiver();
        core.migrate(
            id,
            address(target),
            _signMig(BUYER_PK, id, address(target)),
            _signMig(SELLER_PK, id, address(target))
        );
        // No further action on the migrated agreement.
        vm.prank(buyer);
        vm.expectRevert(NexEscrowCore.NotFunded.selector);
        core.approveMilestone(id, 0);
        MockMigrationReceiver target2 = new MockMigrationReceiver();
        bytes memory bs = _signMig(BUYER_PK, id, address(target2));
        bytes memory ss = _signMig(SELLER_PK, id, address(target2));
        vm.expectRevert(NexEscrowCore.NotFunded.selector);
        core.migrate(id, address(target2), bs, ss);
    }
}
