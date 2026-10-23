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

// Fixed non-party addresses. Resolvers only ever *authorize* rulings; the outsider is an
// unrelated account used to prove no principal reaches a non-party. None may ever appear
// as a settlement beneficiary.
address constant RP = address(0x11aa00000000000000000000000000000000AA11); // primary resolver
address constant RA = address(0x22bb00000000000000000000000000000000Bb22); // appellate resolver
address constant OUT = address(0x33cC00000000000000000000000000000000Cc33); // outsider

uint256 constant PK_A = uint256(0xA11CE); // buyer/seller EOA A
uint256 constant PK_B = uint256(0xB0B); // buyer/seller EOA B
uint256 constant PK_W = uint256(0x3E11E8); // owner key of the EIP-1271 wallet seller

/// @title NexEscrowCoreHandler
/// @notice Handler-driven stateful fuzz driver for NexEscrowCore (closes audit Finding M1).
///         Foundry calls the bounded `act*` entry points in random sequences; each pranks a
///         real actor and performs one externally reachable lifecycle action, swallowing and
///         CLASSIFYING reverts the way a real mempool would (expected state-machine rejection
///         vs. an arithmetic Panic that would signal an implementation defect).
///
/// @dev Independent ("ghost") accounting, maintained here and NEVER by re-reading the same
///      contract variable it is meant to check:
///
///        ghostFunded[A]      — principal successfully pulled INTO the core in asset A
///        ghostWithdrawn[A]   — principal actually paid OUT by `withdraw` in asset A
///        ghostMigratedOut[A] — principal transferred OUT to a migration destination in asset A
///
///      The conservation identity the invariants then assert, per asset A:
///
///        ghostFunded[A] == coreBalance[A] + ghostWithdrawn[A] + ghostMigratedOut[A]
///
///      i.e. every unit funded is, at every reachable state, either still held by the core
///      (escrowed or pending), already withdrawn by buyer/seller, or migrated to the signed
///      destination. coreBalance is the REAL on-chain balance (ground truth), so this is a
///      genuine cross-model check, not a tautology.
contract NexEscrowCoreHandler is Test {
    NexEscrowCore internal immutable CORE;
    MockERC20 internal immutable TOKEN;
    address public immutable BUYER_A;
    address public immutable BUYER_B;
    MockERC1271Wallet public immutable WALLET_W;
    MockMigrationReceiver internal immutable GOOD_RCV;
    RejectingMigrationReceiver internal immutable REJ_RCV;
    RevertingMigrationReceiver internal immutable REV_RCV;

    uint8 internal constant CAP = 12; // max tracked funded agreements (bounds enumeration)
    address internal constant NATIVE = address(0);

    struct Ag {
        uint256 id;
        address asset;
        address buyer;
        address seller;
        uint256 total;
    }

    Ag[] internal ags;

    // Independent accounting (see @dev).
    mapping(address => uint256) public ghostFunded;
    mapping(address => uint256) public ghostWithdrawn;
    mapping(address => uint256) public ghostMigratedOut;
    mapping(uint256 => uint256) public ghostTotal; // id -> funded total

    // State-machine trackers.
    mapping(uint256 => uint8) internal maxCursor;
    mapping(uint256 => bool) internal wasTerminal;
    bool public sawCursorRegression;
    bool public sawTerminalResurrection;
    bool public sawUnexpectedRevert;
    bytes public lastUnexpected;

    // Call classification counters (reported, not asserted).
    uint256 public ghostSuccess;
    uint256 public ghostReject;
    uint256 internal nonceCounter;

    constructor(NexEscrowCore core_, MockERC20 token_) {
        CORE = core_;
        TOKEN = token_;
        BUYER_A = vm.addr(PK_A);
        BUYER_B = vm.addr(PK_B);
        WALLET_W = new MockERC1271Wallet(vm.addr(PK_W));
        GOOD_RCV = new MockMigrationReceiver();
        REJ_RCV = new RejectingMigrationReceiver();
        REV_RCV = new RevertingMigrationReceiver();
        vm.deal(BUYER_A, 1e30);
        vm.deal(BUYER_B, 1e30);
    }

    // ----------------------------------------------------------------------
    // Views used by the invariant contract
    // ----------------------------------------------------------------------

    function agsCount() external view returns (uint256) {
        return ags.length;
    }

    function agAt(uint256 i)
        external
        view
        returns (uint256 id, address asset, address buyer, address seller, uint256 total)
    {
        Ag storage a = ags[i];
        return (a.id, a.asset, a.buyer, a.seller, a.total);
    }

    // ----------------------------------------------------------------------
    // Internal helpers
    // ----------------------------------------------------------------------

    function _pkFor(address who) internal view returns (uint256) {
        if (who == BUYER_A) return PK_A;
        if (who == BUYER_B) return PK_B;
        if (who == address(WALLET_W)) return PK_W; // 1271 wallet defers to its owner key
        return 0;
    }

    function _signAs(address who, bytes32 digest) internal returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_pkFor(who), digest);
        return abi.encodePacked(r, s, v);
    }

    /// @dev Expected state-machine rejections (custom errors) are tolerated; an arithmetic
    ///      Panic(uint256) (overflow/underflow/division/array OOB) is flagged as a potential
    ///      implementation defect for the invariant layer to surface.
    function _classify(bytes memory err) internal {
        ghostReject += 1;
        if (
            err.length >= 4 && err[0] == bytes1(0x4e) && err[1] == bytes1(0x48)
                && err[2] == bytes1(0x7b) && err[3] == bytes1(0x71)
        ) {
            sawUnexpectedRevert = true;
            lastUnexpected = err;
        }
    }

    function _track(uint256 id) internal {
        uint8 c = CORE.nextMilestoneOf(id);
        if (c < maxCursor[id]) sawCursorRegression = true;
        else if (c > maxCursor[id]) maxCursor[id] = c;
        (,,,,,,,,, NexEscrowCore.AgreementStatus st) = CORE.agreements(id);
        bool terminal = st == NexEscrowCore.AgreementStatus.Completed
            || st == NexEscrowCore.AgreementStatus.Migrated;
        if (wasTerminal[id] && !terminal) sawTerminalResurrection = true;
        if (terminal) wasTerminal[id] = true;
    }

    function _pick(uint256 seed) internal view returns (Ag memory) {
        return ags[seed % ags.length];
    }

    function _policy(bool useAppeal, uint256 wSeed, uint16 bpsSeed)
        internal
        pure
        returns (NexEscrowCore.ResolutionPolicy memory p)
    {
        p.primaryResolver = RP;
        p.evidenceWindow = uint40(bound(uint256(keccak256(abi.encode(wSeed, "e"))), 0, 5 days));
        p.rulingWindow = uint40(bound(uint256(keccak256(abi.encode(wSeed, "r"))), 1, 10 days));
        p.timeoutBuyerBps = uint16(bound(uint256(bpsSeed), 0, 10_000));
        p.policyHash = keccak256("policy-doc");
        if (useAppeal) {
            p.appellateResolver = RA;
            p.appealWindow = uint40(bound(uint256(keccak256(abi.encode(wSeed, "a"))), 1, 30 days));
        }
    }

    // ----------------------------------------------------------------------
    // Actions (fuzz entry points)
    // ----------------------------------------------------------------------

    /// activate + fund a fresh agreement (native or ERC-20; EOA or 1271 seller; +/- appeal).
    function actCreateFunded(
        uint256 seed,
        uint8 nRaw,
        uint8 whoSeed,
        bool useToken,
        bool useAppeal,
        uint256 wSeed,
        uint16 bpsSeed
    ) external {
        if (ags.length >= CAP) return;

        address buyer = (whoSeed & 1) == 0 ? BUYER_A : BUYER_B;
        address[3] memory cand = [BUYER_A, BUYER_B, address(WALLET_W)];
        address seller = cand[(uint256(whoSeed) >> 1) % 3];
        if (seller == buyer) seller = address(WALLET_W); // WALLET_W is never a buyer -> always distinct

        uint256 n = bound(uint256(nRaw), 1, 5);
        uint128[] memory amounts = new uint128[](n);
        uint256 total;
        for (uint256 i; i < n; ++i) {
            uint128 amt = uint128(bound(uint256(keccak256(abi.encode(seed, i))), 1, 1e21));
            amounts[i] = amt;
            total += amt;
        }

        address asset = useToken ? address(TOKEN) : NATIVE;
        NexEscrowCore.ResolutionPolicy memory p = _policy(useAppeal, wSeed, bpsSeed);

        NexEscrowCore.AgreementIntent memory intent = NexEscrowCore.AgreementIntent({
            buyer: buyer,
            seller: seller,
            settlementAsset: asset,
            totalAmount: total,
            milestonesHash: CORE.hashMilestones(amounts),
            termsHash: keccak256("terms"),
            resolutionPolicyHash: CORE.hashPolicy(p),
            fundingDeadline: 0,
            executionDeadline: 0,
            nonce: ++nonceCounter
        });

        bytes32 d = CORE.hashIntent(intent);
        uint256 id;
        try CORE.activate(intent, _signAs(buyer, d), _signAs(seller, d)) returns (uint256 newId) {
            id = newId;
        } catch (bytes memory err) {
            _classify(err);
            return;
        }

        if (asset == NATIVE) {
            vm.prank(buyer);
            try CORE.fund{ value: total }(id, amounts, p) {
                _onFunded(id, asset, buyer, seller, total);
            } catch (bytes memory err) {
                _classify(err);
            }
        } else {
            TOKEN.mint(buyer, total);
            vm.startPrank(buyer);
            TOKEN.approve(address(CORE), total);
            try CORE.fund(id, amounts, p) {
                _onFunded(id, asset, buyer, seller, total);
            } catch (bytes memory err) {
                _classify(err);
            }
            vm.stopPrank();
        }
    }

    function _onFunded(uint256 id, address asset, address buyer, address seller, uint256 total)
        internal
    {
        ags.push(Ag({ id: id, asset: asset, buyer: buyer, seller: seller, total: total }));
        ghostFunded[asset] += total;
        ghostTotal[id] = total;
        ghostSuccess += 1;
        _track(id);
    }

    function actApprove(uint256 idSeed) external {
        if (ags.length == 0) return;
        Ag memory a = _pick(idSeed);
        uint8 cursor = CORE.nextMilestoneOf(a.id);
        vm.prank(a.buyer);
        try CORE.approveMilestone(a.id, cursor) {
            ghostSuccess += 1;
        } catch (bytes memory err) {
            _classify(err);
        }
        _track(a.id);
    }

    function actDispute(uint256 idSeed, bool bySeller) external {
        if (ags.length == 0) return;
        Ag memory a = _pick(idSeed);
        uint8 cursor = CORE.nextMilestoneOf(a.id);
        vm.prank(bySeller ? a.seller : a.buyer);
        try CORE.disputeMilestone(a.id, cursor) {
            ghostSuccess += 1;
        } catch (bytes memory err) {
            _classify(err);
        }
        _track(a.id);
    }

    function actSubmitEvidence(uint256 idSeed, bool bySeller, bytes32 h) external {
        if (ags.length == 0) return;
        Ag memory a = _pick(idSeed);
        uint8 cursor = CORE.nextMilestoneOf(a.id);
        vm.prank(bySeller ? a.seller : a.buyer);
        try CORE.submitEvidence(a.id, cursor, h, "") {
            ghostSuccess += 1;
        } catch (bytes memory err) {
            _classify(err);
        }
        _track(a.id);
    }

    // Is the agreement's current (cursor) milestone actually under dispute? Guards the deadline
    // views below so they are never indexed out of range for a settled/completed agreement —
    // keeping every core interaction inside the try/catch classifier, never a handler revert.
    function _currentIsDisputed(uint256 id, uint8 cursor) internal view returns (bool) {
        NexEscrowCore.Milestone[] memory ms = CORE.milestonesOf(id);
        return cursor < ms.length && ms[cursor].status == NexEscrowCore.MilestoneStatus.Disputed;
    }

    function _warpIntoRulingWindow(uint256 id, uint8 cursor) internal {
        if (!_currentIsDisputed(id, cursor)) return;
        (uint256 eD,) = CORE.disputeDeadlines(id, cursor);
        if (block.timestamp < eD) vm.warp(eD);
    }

    function _warpPastRulingDeadline(uint256 id, uint8 cursor) internal {
        if (!_currentIsDisputed(id, cursor)) return;
        (, uint256 rD) = CORE.disputeDeadlines(id, cursor);
        if (block.timestamp < rD) vm.warp(rD);
    }

    function actRule(uint256 idSeed, uint16 bpsRaw) external {
        if (ags.length == 0) return;
        Ag memory a = _pick(idSeed);
        uint8 cursor = CORE.nextMilestoneOf(a.id);
        _warpIntoRulingWindow(a.id, cursor);
        vm.prank(RP);
        try CORE.rule(a.id, cursor, uint16(bound(uint256(bpsRaw), 0, 10_000))) {
            ghostSuccess += 1;
        } catch (bytes memory err) {
            _classify(err);
        }
        _track(a.id);
    }

    function actFinalizeTimeout(uint256 idSeed) external {
        if (ags.length == 0) return;
        Ag memory a = _pick(idSeed);
        uint8 cursor = CORE.nextMilestoneOf(a.id);
        _warpPastRulingDeadline(a.id, cursor);
        vm.prank(OUT); // anyone may finalize
        try CORE.finalizeTimeout(a.id, cursor) {
            ghostSuccess += 1;
        } catch (bytes memory err) {
            _classify(err);
        }
        _track(a.id);
    }

    function actAppeal(uint256 idSeed, bool bySeller) external {
        if (ags.length == 0) return;
        Ag memory a = _pick(idSeed);
        uint8 cursor = CORE.nextMilestoneOf(a.id);
        vm.prank(bySeller ? a.seller : a.buyer);
        try CORE.appeal(a.id, cursor) {
            ghostSuccess += 1;
        } catch (bytes memory err) {
            _classify(err);
        }
        _track(a.id);
    }

    function actFinalRule(uint256 idSeed, uint16 bpsRaw) external {
        if (ags.length == 0) return;
        Ag memory a = _pick(idSeed);
        uint8 cursor = CORE.nextMilestoneOf(a.id);
        vm.prank(RA);
        try CORE.finalRule(a.id, cursor, uint16(bound(uint256(bpsRaw), 0, 10_000))) {
            ghostSuccess += 1;
        } catch (bytes memory err) {
            _classify(err);
        }
        _track(a.id);
    }

    function actFinalizeRuling(uint256 idSeed, uint256 warpSeed) external {
        if (ags.length == 0) return;
        Ag memory a = _pick(idSeed);
        uint8 cursor = CORE.nextMilestoneOf(a.id);
        vm.warp(block.timestamp + bound(warpSeed, 1, 45 days)); // likely past appeal/appellate window
        vm.prank(OUT); // anyone may finalize a standing ruling
        try CORE.finalizeRuling(a.id, cursor) {
            ghostSuccess += 1;
        } catch (bytes memory err) {
            _classify(err);
        }
        _track(a.id);
    }

    function actWithdraw(uint256 actorSeed, bool nativeSel) external {
        address[3] memory bs = [BUYER_A, BUYER_B, address(WALLET_W)];
        address actor = bs[actorSeed % 3];
        address asset = nativeSel ? NATIVE : address(TOKEN);
        uint256 pending = CORE.pendingWithdrawals(actor, asset);
        vm.prank(actor);
        try CORE.withdraw(asset) {
            ghostWithdrawn[asset] += pending; // exactly `pending` left the core
            ghostSuccess += 1;
        } catch (bytes memory err) {
            _classify(err); // e.g. a 1271 wallet with no receive() fails the native push; pending stays
        }
    }

    function actMigrate(uint256 idSeed, uint8 rcvSeed) external {
        if (ags.length == 0) return;
        Ag memory a = _pick(idSeed);
        address target = rcvSeed % 3 == 0
            ? address(GOOD_RCV)
            : (rcvSeed % 3 == 1 ? address(REJ_RCV) : address(REV_RCV));

        uint256 preEscrow = CORE.escrowedOf(a.id);
        bytes32 d = CORE.hashMigration(a.id, target);
        bytes memory bSig = _signAs(a.buyer, d);
        bytes memory sSig = _signAs(a.seller, d);

        try CORE.migrate(a.id, target, bSig, sSig) {
            ghostMigratedOut[a.asset] += preEscrow; // the remaining principal left the core
            ghostSuccess += 1;
        } catch (bytes memory err) {
            _classify(err);
            // Failed migration must be atomic: the source financial state is unchanged.
            if (CORE.escrowedOf(a.id) != preEscrow) {
                sawUnexpectedRevert = true;
                lastUnexpected = err;
            }
        }
        _track(a.id);
    }

    function actWarp(uint256 dt) external {
        vm.warp(block.timestamp + bound(dt, 1, 10 days));
    }
}

/// @title NexEscrowCoreInvariantsTest
/// @notice Stateful settlement/conservation invariants for NexEscrowCore (closes Finding M1).
///         Reference architecture: the Demo 0 handler-driven suite NexusEscrow.Invariants.t.sol
///         (EscrowHandler + targetContract + independent-sum invariants). This mirrors that
///         pattern for the Demo 1 pull-payment kernel, adding dispute/appeal/timeout/migration
///         paths and an independent ghost model rather than milestone-only solvency.
contract NexEscrowCoreInvariantsTest is Test {
    NexEscrowCore internal core;
    MockERC20 internal token;
    NexEscrowCoreHandler internal handler;

    address internal constant NATIVE = address(0);

    function setUp() public {
        core = new NexEscrowCore();
        token = new MockERC20("Invariant", "INV");
        handler = new NexEscrowCoreHandler(core, token);

        // Every actor must be distinct, or the "resolver/outsider never receive principal"
        // invariants would be vacuous.
        address[6] memory who =
            [handler.BUYER_A(), handler.BUYER_B(), address(handler.WALLET_W()), RP, RA, OUT];
        for (uint256 i; i < 6; ++i) {
            for (uint256 j = i + 1; j < 6; ++j) {
                assertTrue(who[i] != who[j], "actor collision");
            }
        }

        // Focus the fuzzer on the lifecycle actions (not the view getters).
        bytes4[] memory sel = new bytes4[](12);
        sel[0] = handler.actCreateFunded.selector;
        sel[1] = handler.actApprove.selector;
        sel[2] = handler.actDispute.selector;
        sel[3] = handler.actSubmitEvidence.selector;
        sel[4] = handler.actRule.selector;
        sel[5] = handler.actFinalizeTimeout.selector;
        sel[6] = handler.actAppeal.selector;
        sel[7] = handler.actFinalRule.selector;
        sel[8] = handler.actFinalizeRuling.selector;
        sel[9] = handler.actWithdraw.selector;
        sel[10] = handler.actMigrate.selector;
        sel[11] = handler.actWarp.selector;
        targetSelector(FuzzSelector({ addr: address(handler), selectors: sel }));
        targetContract(address(handler));
    }

    // ---- independent sums over the contract's real state -------------------

    function _bal(address asset) internal view returns (uint256) {
        return asset == NATIVE ? address(core).balance : token.balanceOf(address(core));
    }

    function _sumEscrowed(address asset) internal view returns (uint256 s) {
        uint256 n = handler.agsCount();
        for (uint256 i; i < n; ++i) {
            (uint256 id, address a,,,) = handler.agAt(i);
            if (a == asset) s += core.escrowedOf(id);
        }
    }

    function _sumPending(address asset) internal view returns (uint256 s) {
        address[3] memory bs = [handler.BUYER_A(), handler.BUYER_B(), address(handler.WALLET_W())];
        for (uint256 i; i < 3; ++i) {
            s += core.pendingWithdrawals(bs[i], asset);
        }
    }

    function _assets() internal view returns (address[2] memory) {
        return [NATIVE, address(token)];
    }

    // ---- INV-D1: conservation (independent ghost model vs real balance) ----

    function invariant_D1_Conservation() public view {
        address[2] memory a = _assets();
        for (uint256 i; i < 2; ++i) {
            assertEq(
                handler.ghostFunded(a[i]),
                _bal(a[i]) + handler.ghostWithdrawn(a[i]) + handler.ghostMigratedOut(a[i]),
                "D1: funded != held + withdrawn + migrated"
            );
        }
    }

    // ---- INV-D1b: the contract's internal books are backed by the real balance ----

    function invariant_D1b_BalanceBacksBooks() public view {
        address[2] memory a = _assets();
        for (uint256 i; i < 2; ++i) {
            assertEq(
                _bal(a[i]),
                _sumEscrowed(a[i]) + _sumPending(a[i]),
                "D1b: balance != escrowed + pending"
            );
        }
    }

    // ---- INV-D2: a resolver can rule but never receives principal ----

    function invariant_D2_ResolverNoPrincipal() public view {
        address[2] memory a = _assets();
        for (uint256 i; i < 2; ++i) {
            assertEq(core.pendingWithdrawals(RP, a[i]), 0, "D2: primary resolver credited");
            assertEq(core.pendingWithdrawals(RA, a[i]), 0, "D2: appellate resolver credited");
        }
    }

    // ---- INV-D3: no principal reaches an unauthorized (non-party) recipient ----

    function invariant_D3_NoUnauthorizedRecipient() public view {
        address[2] memory a = _assets();
        for (uint256 i; i < 2; ++i) {
            assertEq(core.pendingWithdrawals(OUT, a[i]), 0, "D3: outsider credited");
        }
        // Principal only ever reaches buyer/seller (withdrawn) or the signed migration target
        // (migrated); D1 already accounts every funded unit through exactly those channels.
    }

    // ---- INV-D4: per-agreement books tie to the milestone schedule; cursor monotonic ----

    function invariant_D4_PerAgreementConsistency() public view {
        uint256 n = handler.agsCount();
        for (uint256 i; i < n; ++i) {
            (uint256 id,,,,) = handler.agAt(i);
            uint8 cursor = core.nextMilestoneOf(id);
            NexEscrowCore.Milestone[] memory ms = core.milestonesOf(id);
            assertLe(uint256(cursor), ms.length, "D4: cursor out of range");

            (,,,,,,,,, NexEscrowCore.AgreementStatus st) = core.agreements(id);
            if (st == NexEscrowCore.AgreementStatus.Funded) {
                uint256 locked;
                for (uint256 j = cursor; j < ms.length; ++j) {
                    locked += ms[j].amount;
                }
                assertEq(core.escrowedOf(id), locked, "D4: escrowed != sum(unsettled milestones)");
            } else if (st == NexEscrowCore.AgreementStatus.Migrated) {
                assertEq(core.escrowedOf(id), 0, "D4: migrated but still escrowed");
            } else if (st == NexEscrowCore.AgreementStatus.Completed) {
                assertEq(core.escrowedOf(id), 0, "D4: completed but still escrowed");
                assertEq(uint256(cursor), ms.length, "D4: completed cursor not at end");
            }
        }
    }

    // ---- INV-D5: remaining principal never exceeds originally funded ----

    function invariant_D5_RemainingBounds() public view {
        uint256 n = handler.agsCount();
        for (uint256 i; i < n; ++i) {
            (uint256 id,,,,) = handler.agAt(i);
            assertLe(core.escrowedOf(id), handler.ghostTotal(id), "D5: remaining > funded");
        }
    }

    // ---- INV-D6: pending withdrawals are fully backed by held balance ----

    function invariant_D6_PendingBacked() public view {
        address[2] memory a = _assets();
        for (uint256 i; i < 2; ++i) {
            assertGe(_bal(a[i]), _sumPending(a[i]), "D6: pending not backed");
        }
    }

    // ---- INV state-machine: monotonic cursor, terminal states final, no arithmetic Panic ----
    // (D7 migration conservation is carried by D1's ghostMigratedOut plus the handler's
    //  per-call atomicity check, which trips sawUnexpectedRevert if a failed migration ever
    //  changed the source's escrowed balance.)

    function invariant_StateMachine() public view {
        assertFalse(handler.sawCursorRegression(), "cursor regressed");
        assertFalse(handler.sawTerminalResurrection(), "terminal agreement resumed");
        assertFalse(handler.sawUnexpectedRevert(), "arithmetic panic / non-atomic migration");
    }

    /// @notice Non-vacuity + concrete coverage. A scripted deep sequence must actually MOVE the
    ///         ghost accounting (fund, withdraw, and migration all exercised, including a 1271
    ///         seller whose native withdrawal fails) and still conserve — proving the fuzz
    ///         invariants above are not vacuously true on an empty system.
    function test_Harness_DrivesDeepStatesAndConserves() public {
        handler.actCreateFunded(1, 2, 2, false, false, 1, 5000); // ag0: native, EOA seller, 2 ms
        handler.actCreateFunded(2, 1, 0, true, false, 2, 5000); // ag1: ERC-20, 1271 seller, 1 ms
        handler.actCreateFunded(3, 2, 5, false, false, 3, 0); // ag2: native, 1271 seller, timeout->seller
        handler.actCreateFunded(4, 3, 0, false, true, 4, 3000); // ag3: native, appeal policy, 3 ms
        assertEq(handler.agsCount(), 4, "all four funded");

        handler.actApprove(0); // ag0 ms0 -> seller
        handler.actApprove(0); // ag0 ms1 -> seller => Completed
        handler.actDispute(1, false); // ag1 disputed
        handler.actRule(1, 3000); // ag1 ruled 30/70 (appealWindow 0 => final)
        handler.actDispute(2, true); // ag2 disputed by seller
        handler.actFinalizeTimeout(2); // ag2 timeout split (bps 0 => all to seller)
        handler.actMigrate(3, 0); // ag3 migrated to the well-behaved receiver

        for (uint256 k; k < 3; ++k) {
            handler.actWithdraw(k, true); // native (the 1271 seller's native withdraw fails, caught)
            handler.actWithdraw(k, false); // ERC-20
        }

        // The harness actually transitioned state (non-vacuous):
        assertGt(handler.ghostFunded(address(0)), 0, "no native funded");
        assertGt(handler.ghostFunded(address(token)), 0, "no token funded");
        assertGt(handler.ghostWithdrawn(address(0)), 0, "no native withdrawn");
        assertGt(handler.ghostWithdrawn(address(token)), 0, "no token withdrawn");
        assertGt(handler.ghostMigratedOut(address(0)), 0, "nothing migrated");

        // ...and conservation holds on this concrete deep sequence.
        assertEq(
            handler.ghostFunded(address(0)),
            _bal(address(0)) + handler.ghostWithdrawn(address(0))
                + handler.ghostMigratedOut(address(0)),
            "native conservation"
        );
        assertEq(
            handler.ghostFunded(address(token)),
            _bal(address(token)) + handler.ghostWithdrawn(address(token))
                + handler.ghostMigratedOut(address(token)),
            "token conservation"
        );

        // Terminal states were reached.
        (uint256 id0,,,,) = handler.agAt(0);
        (uint256 id3,,,,) = handler.agAt(3);
        (,,,,,,,,, NexEscrowCore.AgreementStatus s0) = core.agreements(id0);
        (,,,,,,,,, NexEscrowCore.AgreementStatus s3) = core.agreements(id3);
        assertEq(uint8(s0), uint8(NexEscrowCore.AgreementStatus.Completed), "ag0 completed");
        assertEq(uint8(s3), uint8(NexEscrowCore.AgreementStatus.Migrated), "ag3 migrated");
    }
}
