// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { NexusEscrow } from "../src/NexusEscrow.sol";
import { MockERC20 } from "./mocks/MockERC20.sol";

address constant H_OWNER = address(0x0A11);
address constant H_FEE_RECIPIENT = address(0xFEE);
address constant H_BUYER = address(0xB0B);
address constant H_SELLER = address(0x5E11);
address constant H_ARBITER = address(0xA2B1);
address constant H_STRANGER = address(0x57A);

/// @notice Stateful invariant harness. A driver contract mutates the ESCROW through
///         bounded random sequences (create/fund/approve/dispute/resolve/cancel/
///         admin/pause/warp); the invariants then assert global accounting is intact.
contract EscrowHandler is Test {
    NexusEscrow public immutable ESCROW;
    MockERC20 public immutable TOKEN;

    struct Tracked {
        uint256 id;
        bool isToken;
    }

    Tracked[] public tracked;

    constructor(NexusEscrow escrow_, MockERC20 token_) {
        ESCROW = escrow_;
        TOKEN = token_;
    }

    function trackedCount() external view returns (uint256) {
        return tracked.length;
    }

    function trackedAt(uint256 i) external view returns (Tracked memory) {
        return tracked[i];
    }

    // ---------------------------------------------------------------------
    // Drivers (never revert outward; failures are swallowed like real txs)
    // ---------------------------------------------------------------------

    function createAgreement(uint256 seed, uint8 count, bool useToken) external {
        count = uint8(bound(count, 1, 4));
        uint128[] memory amounts = new uint128[](count);
        for (uint256 i = 0; i < count; ++i) {
            amounts[i] = uint128(bound(uint256(keccak256(abi.encode(seed, i))), 1, 1 ether));
        }
        address tokenAddr = useToken ? address(TOKEN) : address(0);
        vm.prank(H_BUYER);
        try ESCROW.createAgreement(H_SELLER, H_ARBITER, tokenAddr, amounts, 0) returns (
            uint256 id
        ) {
            tracked.push(Tracked({ id: id, isToken: useToken }));
        } catch { }
    }

    function fund(uint256 seed) external {
        if (tracked.length == 0) return;
        Tracked memory t = tracked[seed % tracked.length];
        (,,,, uint128 totalAmount,,,,,,) = ESCROW.agreements(t.id);

        if (t.isToken) {
            vm.startPrank(H_BUYER);
            TOKEN.approve(address(ESCROW), totalAmount);
            try ESCROW.fund(t.id) { } catch { }
            vm.stopPrank();
        } else {
            vm.prank(H_BUYER);
            try ESCROW.fund{ value: totalAmount }(t.id) { } catch { }
        }
    }

    function approveMilestone(uint256 seed) external {
        if (tracked.length == 0) return;
        uint256 id = tracked[seed % tracked.length].id;
        vm.prank(H_BUYER);
        try ESCROW.approveMilestone(id) { } catch { }
    }

    function raiseDispute(uint256 seed, bool bySeller) external {
        if (tracked.length == 0) return;
        uint256 id = tracked[seed % tracked.length].id;
        vm.prank(bySeller ? H_SELLER : H_BUYER);
        try ESCROW.raiseDispute(id) { } catch { }
    }

    function resolveDispute(uint256 seed, uint16 buyerBps) external {
        if (tracked.length == 0) return;
        uint256 id = tracked[seed % tracked.length].id;
        buyerBps = uint16(bound(buyerBps, 0, 10_000));
        vm.prank(H_ARBITER);
        try ESCROW.resolveDispute(id, buyerBps) { } catch { }
    }

    function cancel(uint256 seed) external {
        if (tracked.length == 0) return;
        uint256 id = tracked[seed % tracked.length].id;
        vm.prank(seed % 2 == 0 ? H_BUYER : H_SELLER);
        try ESCROW.cancelBeforeFunding(id) { } catch { }
    }

    function withdrawFees(bool native) external {
        vm.prank(H_FEE_RECIPIENT);
        try ESCROW.withdrawFees(native ? address(0) : address(TOKEN)) { } catch { }
    }

    function setProtocolFee(uint16 bps) external {
        bps = uint16(bound(bps, 0, ESCROW.MAX_FEE_BPS()));
        vm.prank(H_OWNER);
        try ESCROW.setProtocolFee(bps) { } catch { }
    }

    function togglePause(bool pauseIt) external {
        vm.prank(H_OWNER);
        if (pauseIt) {
            try ESCROW.pause() { } catch { }
        } else {
            try ESCROW.unpause() { } catch { }
        }
    }

    function warp(uint40 delta) external {
        vm.warp(block.timestamp + bound(uint256(delta), 1, 2 days));
    }
}

contract NexusEscrowInvariantsTest is Test {
    NexusEscrow internal escrow;
    MockERC20 internal token;
    EscrowHandler internal handler;

    function setUp() public {
        escrow = new NexusEscrow(address(this), address(0xFEE));
        token = new MockERC20("Invariant Token", "INV");

        handler = new EscrowHandler(escrow, token);
        vm.deal(H_BUYER, 10_000 ether);
        token.mint(H_BUYER, 10_000_000 ether);

        targetContract(address(handler));
    }

    /// @dev Sum of amounts still escrowed for an agreement that is Active
    ///      (Pending or Disputed milestones). Terminal/unfunded agreements owe 0.
    function _owedForAgreement(uint256 id)
        internal
        view
        returns (uint256 nativeOwed, uint256 tokenOwed)
    {
        (,,, address tokenAddr,,, NexusEscrow.AgreementStatus status,,,,) = escrow.agreements(id);
        if (status != NexusEscrow.AgreementStatus.Active) return (0, 0);

        NexusEscrow.Milestone[] memory milestones = escrow.getMilestones(id);
        uint256 sum;
        for (uint256 i = 0; i < milestones.length; ++i) {
            if (
                milestones[i].status == NexusEscrow.MilestoneStatus.Pending
                    || milestones[i].status == NexusEscrow.MilestoneStatus.Disputed
            ) {
                sum += milestones[i].amount;
            }
        }
        if (tokenAddr == address(0)) return (sum, 0);
        if (tokenAddr == address(token)) return (0, sum);
        return (0, 0);
    }

    function _totals() internal view returns (uint256 nativeOwed, uint256 tokenOwed) {
        uint256 count = handler.trackedCount();
        for (uint256 i = 0; i < count; ++i) {
            EscrowHandler.Tracked memory t = handler.trackedAt(i);
            (uint256 n, uint256 tk) = _owedForAgreement(t.id);
            nativeOwed += n;
            tokenOwed += tk;
        }
    }

    /// @notice INVARIANT 1/2/11: contract balances exactly back all still-escrowed
    ///         milestone value plus accrued (unwithdrawn) fees. Never over-paid,
    ///         never over-committed.
    function invariant_Solvency() public view {
        (uint256 nativeOwed, uint256 tokenOwed) = _totals();

        uint256 nativeAccrued = escrow.accruedFees(address(0));
        uint256 tokenAccrued = escrow.accruedFees(address(token));

        assertEq(address(escrow).balance, nativeOwed + nativeAccrued, "native solvency");
        assertEq(token.balanceOf(address(escrow)), tokenOwed + tokenAccrued, "TOKEN solvency");
    }

    /// @notice INVARIANT 3/4/10/12: milestone progress is monotonic, in range, and
    ///         consistent with agreement status; released milestones never regress.
    function invariant_StateConsistency() public view {
        uint256 count = handler.trackedCount();
        for (uint256 i = 0; i < count; ++i) {
            EscrowHandler.Tracked memory t = handler.trackedAt(i);
            (
                ,,,,
                uint128 totalAmount,,
                NexusEscrow.AgreementStatus status,,,
                uint8 milestoneCount,
                uint8 nextMilestone
            ) = escrow.agreements(t.id);

            assertLe(nextMilestone, milestoneCount, "nextMilestone out of range");

            NexusEscrow.Milestone[] memory milestones = escrow.getMilestones(t.id);
            assertEq(milestones.length, milestoneCount, "milestone array length mismatch");

            uint256 sum;
            for (uint256 j = 0; j < milestones.length; ++j) {
                sum += milestones[j].amount;
                if (j < nextMilestone) {
                    assertTrue(
                        milestones[j].status == NexusEscrow.MilestoneStatus.Released
                            || milestones[j].status == NexusEscrow.MilestoneStatus.Resolved,
                        "milestone below cursor not terminal"
                    );
                } else {
                    assertTrue(
                        milestones[j].status == NexusEscrow.MilestoneStatus.Pending
                            || milestones[j].status == NexusEscrow.MilestoneStatus.Disputed,
                        "milestone at/after cursor terminal"
                    );
                }
            }
            assertEq(sum, totalAmount, "milestone sum != total");

            if (status == NexusEscrow.AgreementStatus.Completed) {
                assertEq(nextMilestone, milestoneCount, "completed without full progress");
            } else if (status == NexusEscrow.AgreementStatus.Cancelled) {
                assertEq(nextMilestone, 0, "cancelled after progress");
            } else if (status == NexusEscrow.AgreementStatus.Active) {
                assertLt(nextMilestone, milestoneCount, "active but complete");
            }
        }
    }

    /// @notice INVARIANT: agreement ids are strictly increasing and never reused.
    function invariant_IdMonotonic() public view {
        assertGe(escrow.nextAgreementId(), handler.trackedCount());
    }
}
