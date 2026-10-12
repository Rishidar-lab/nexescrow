// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title NexEscrowCore (Demo 1)
/// @notice Demo 1 settlement kernel. Legacy `NexusEscrow` (Demo 0) is untouched and
///         remains the only deployed instance.
/// @dev Tranches implemented so far (docs/WHITEPAPER_DEMO_1.md):
///      - A (§7): bilateral EIP-712 `AgreementIntent` activation; EIP-1271; digest replay.
///      - B (§4): funding, in-order milestone release, and dispute *liveness* — finite
///        evidence/ruling windows, a deterministic pre-committed timeout split that
///        ANYONE can finalize once the ruling deadline passes, and conservation with no
///        path that pays the resolver.
///      Still deferred: the pluggable `IResolver`/quorum, on-chain evidence-hash events,
///      the appellate path (§5-6, tranche C), bilateral migration (§9, tranche D) and the
///      x402/AP2/ERC-8004 adapters (§8, tranche E). This kernel takes NO protocol fee, so
///      every unit funded is eventually withdrawable by the buyer or the seller only.
///      Payouts are PULL, not push: settlement credits `pendingWithdrawals` and a separate
///      `withdraw` moves funds, so a hostile recipient can never block finalization and no
///      milestone can be frozen forever (whitepaper §4 rule 1).
contract NexEscrowCore is EIP712, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =====================================================================
    // Types — tranche A
    // =====================================================================

    /// @dev `chainId` and `verifyingContract` are bound by the EIP-712 domain, not
    ///      duplicated as fields, so the domain is the single source of chain/contract
    ///      separation and the signed payload is the canonical terms only.
    struct AgreementIntent {
        address buyer;
        address seller;
        address settlementAsset; // address(0) == the chain's native asset
        uint256 totalAmount;
        bytes32 milestonesHash; // commitment to the ordered milestone schedule
        bytes32 termsHash; // commitment to off-chain human-readable terms
        bytes32 resolutionPolicyHash; // commitment to the ResolutionPolicy revealed at funding
        uint64 fundingDeadline; // 0 == no funding deadline
        uint64 executionDeadline; // 0 == no execution deadline
        uint256 nonce; // disambiguates otherwise-identical intents
    }

    enum AgreementStatus {
        None,
        Activated,
        Funded,
        Completed
    }

    struct Agreement {
        address buyer;
        address seller;
        address settlementAsset;
        uint256 totalAmount;
        bytes32 milestonesHash;
        bytes32 termsHash;
        bytes32 resolutionPolicyHash;
        uint64 fundingDeadline;
        uint64 executionDeadline;
        AgreementStatus status;
    }

    // =====================================================================
    // Types — tranche B
    // =====================================================================

    enum MilestoneStatus {
        Pending, // not yet released or disputed
        Released, // buyer approved -> seller paid in full
        Disputed, // under the dispute clock (evidence -> ruling -> timeout)
        Resolved // settled by a resolver ruling or the timeout split
    }

    struct Milestone {
        uint128 amount;
        MilestoneStatus status;
        uint40 disputedAt; // timestamp the dispute was raised; 0 otherwise
    }

    /// @notice Immutable per-agreement dispute policy, committed in the signed intent
    ///         (`resolutionPolicyHash`) and revealed at funding (whitepaper §4.2).
    struct ResolutionPolicy {
        address primaryResolver;
        address appellateResolver; // tranche C — MUST be address(0) here
        uint40 evidenceWindow; // seconds for evidence after a dispute (may be 0)
        uint40 rulingWindow; // seconds the resolver has to rule after evidence (> 0)
        uint40 appealWindow; // tranche C — MUST be 0 here
        uint16 timeoutBuyerBps; // deterministic buyer share if the ruling deadline lapses
        bytes32 policyHash; // commitment to an off-chain policy document
    }

    // =====================================================================
    // Constants
    // =====================================================================

    bytes32 public constant AGREEMENT_INTENT_TYPEHASH = keccak256(
        "AgreementIntent(address buyer,address seller,address settlementAsset,uint256 totalAmount,bytes32 milestonesHash,bytes32 termsHash,bytes32 resolutionPolicyHash,uint64 fundingDeadline,uint64 executionDeadline,uint256 nonce)"
    );

    uint16 public constant BPS_DENOMINATOR = 10_000;
    uint8 public constant MAX_MILESTONES = 50;
    uint40 public constant MAX_WINDOW = 365 days;

    // =====================================================================
    // Storage
    // =====================================================================

    uint256 public nextAgreementId;
    mapping(uint256 => Agreement) public agreements;
    /// @dev typed-data digest => activated. A consumed intent can never activate again.
    mapping(bytes32 => bool) public consumedIntent;

    mapping(uint256 => Milestone[]) internal _milestones;
    mapping(uint256 => ResolutionPolicy) public resolutionPolicyOf;
    /// @dev index of the next milestone that may be approved or disputed (strict order).
    mapping(uint256 => uint8) public nextMilestoneOf;
    /// @dev principal still held in escrow for an agreement (in its settlement asset).
    mapping(uint256 => uint256) public escrowedOf;
    /// @dev account => asset => amount withdrawable (pull payments).
    mapping(address => mapping(address => uint256)) public pendingWithdrawals;

    // =====================================================================
    // Events
    // =====================================================================

    event AgreementActivated(
        uint256 indexed id,
        address indexed buyer,
        address indexed seller,
        bytes32 intentDigest,
        address settlementAsset,
        uint256 totalAmount,
        bytes32 milestonesHash
    );
    event AgreementFunded(uint256 indexed id, uint256 totalAmount, uint256 milestoneCount);
    event MilestoneReleased(uint256 indexed id, uint256 indexed index, uint128 amount);
    event MilestoneDisputed(uint256 indexed id, uint256 indexed index, address indexed by);
    event MilestoneRuled(
        uint256 indexed id,
        uint256 indexed index,
        uint16 buyerBps,
        uint128 buyerAmount,
        uint128 sellerAmount
    );
    event MilestoneTimedOut(
        uint256 indexed id,
        uint256 indexed index,
        uint16 timeoutBuyerBps,
        uint128 buyerAmount,
        uint128 sellerAmount
    );
    event AgreementCompleted(uint256 indexed id);
    event Withdrawal(address indexed account, address indexed asset, uint256 amount);

    // =====================================================================
    // Errors
    // =====================================================================

    error ZeroBuyer();
    error ZeroSeller();
    error IdenticalParties();
    error ZeroAmount();
    error EmptyMilestonesHash();
    error InvalidDeadlines();
    error IntentAlreadyActivated();
    error InvalidBuyerSignature();
    error InvalidSellerSignature();

    error NotActivated();
    error NotFunded();
    error NotBuyer();
    error NotParty();
    error NotResolver();
    error FundingDeadlinePassed();
    error NativeValueMismatch();
    error UnsupportedTokenBehavior();
    error MilestonesHashMismatch();
    error PolicyHashMismatch();
    error InvalidMilestoneCount();
    error MilestoneSumMismatch();
    error InvalidPolicy();
    error AppealNotSupportedYet();
    error WrongMilestone();
    error WrongMilestoneState();
    error TooEarlyToRule();
    error RulingWindowClosed();
    error NotTimeoutEligible();
    error BpsOutOfRange();
    error NothingToWithdraw();
    error NativeTransferFailed();

    constructor() EIP712("NexEscrowCore", "1") { }

    // =====================================================================
    // Views
    // =====================================================================

    /// @notice EIP-712 typed-data digest for an intent, bound to this chain and contract.
    function hashIntent(AgreementIntent calldata intent) public view returns (bytes32) {
        return _hashTypedDataV4(_structHash(intent));
    }

    /// @notice Whether an intent has already been activated (consumed).
    function isIntentConsumed(AgreementIntent calldata intent) external view returns (bool) {
        return consumedIntent[_hashTypedDataV4(_structHash(intent))];
    }

    /// @notice The EIP-712 domain separator for this deployment (chain + contract bound).
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @notice The revealed milestone schedule for a funded agreement.
    function milestonesOf(uint256 id) external view returns (Milestone[] memory) {
        return _milestones[id];
    }

    /// @notice Canonical commitment for a milestone schedule (what the intent commits to).
    function hashMilestones(uint128[] calldata amounts) external pure returns (bytes32) {
        return keccak256(abi.encode(amounts));
    }

    /// @notice Canonical commitment for a resolution policy (what the intent commits to).
    function hashPolicy(ResolutionPolicy calldata policy) external pure returns (bytes32) {
        return keccak256(abi.encode(policy));
    }

    /// @notice Dispute deadlines for the current (disputed) milestone, derived from the
    ///         policy windows. Returns (evidenceDeadline, rulingDeadline); both 0 if the
    ///         milestone is not disputed.
    function disputeDeadlines(uint256 id, uint256 index)
        external
        view
        returns (uint256 evidenceDeadline, uint256 rulingDeadline)
    {
        Milestone storage m = _milestones[id][index];
        if (m.status != MilestoneStatus.Disputed) return (0, 0);
        ResolutionPolicy storage p = resolutionPolicyOf[id];
        evidenceDeadline = uint256(m.disputedAt) + p.evidenceWindow;
        rulingDeadline = evidenceDeadline + p.rulingWindow;
    }

    // =====================================================================
    // Tranche A — activation
    // =====================================================================

    /// @notice Activate a bilateral agreement from a doubly-signed EIP-712 intent.
    /// @dev Both signatures are checked with EIP-1271-aware validation (EOA + smart
    ///      account), fail-closed. The digest is consumed so the same intent can never
    ///      activate twice (invariant 7). No funds move here.
    function activate(
        AgreementIntent calldata intent,
        bytes calldata buyerSignature,
        bytes calldata sellerSignature
    ) external returns (uint256 id) {
        if (intent.buyer == address(0)) revert ZeroBuyer();
        if (intent.seller == address(0)) revert ZeroSeller();
        if (intent.buyer == intent.seller) revert IdenticalParties();
        if (intent.totalAmount == 0) revert ZeroAmount();
        if (intent.milestonesHash == bytes32(0)) revert EmptyMilestonesHash();
        _validateDeadlines(intent.fundingDeadline, intent.executionDeadline);

        bytes32 digest = _hashTypedDataV4(_structHash(intent));
        if (consumedIntent[digest]) revert IntentAlreadyActivated();

        if (!SignatureChecker.isValidSignatureNow(intent.buyer, digest, buyerSignature)) {
            revert InvalidBuyerSignature();
        }
        if (!SignatureChecker.isValidSignatureNow(intent.seller, digest, sellerSignature)) {
            revert InvalidSellerSignature();
        }

        consumedIntent[digest] = true;

        id = nextAgreementId++;
        agreements[id] = Agreement({
            buyer: intent.buyer,
            seller: intent.seller,
            settlementAsset: intent.settlementAsset,
            totalAmount: intent.totalAmount,
            milestonesHash: intent.milestonesHash,
            termsHash: intent.termsHash,
            resolutionPolicyHash: intent.resolutionPolicyHash,
            fundingDeadline: intent.fundingDeadline,
            executionDeadline: intent.executionDeadline,
            status: AgreementStatus.Activated
        });

        emit AgreementActivated(
            id,
            intent.buyer,
            intent.seller,
            digest,
            intent.settlementAsset,
            intent.totalAmount,
            intent.milestonesHash
        );
    }

    // =====================================================================
    // Tranche B — funding, release, dispute liveness
    // =====================================================================

    /// @notice Buyer funds an activated agreement, revealing the committed milestone
    ///         schedule and resolution policy. Commit-reveal: the revealed values must
    ///         hash to the commitments in the signed intent.
    /// @dev Pulls the full `totalAmount` (native via msg.value, or ERC-20 via
    ///      transferFrom with a fee-on-transfer balance-delta guard). The policy's
    ///      timeout disposition is now immutable — no admin can invent one later
    ///      (whitepaper §4.2 rule 2). Appeal fields must be empty in this tranche.
    function fund(uint256 id, uint128[] calldata milestoneAmounts, ResolutionPolicy calldata policy)
        external
        payable
        nonReentrant
    {
        Agreement storage a = agreements[id];
        if (a.status != AgreementStatus.Activated) revert NotActivated();
        if (msg.sender != a.buyer) revert NotBuyer();
        if (a.fundingDeadline != 0 && block.timestamp > a.fundingDeadline) {
            revert FundingDeadlinePassed();
        }

        uint256 n = milestoneAmounts.length;
        if (n == 0 || n > MAX_MILESTONES) revert InvalidMilestoneCount();
        if (keccak256(abi.encode(milestoneAmounts)) != a.milestonesHash) {
            revert MilestonesHashMismatch();
        }
        if (keccak256(abi.encode(policy)) != a.resolutionPolicyHash) revert PolicyHashMismatch();
        _validatePolicy(policy, a.buyer, a.seller);

        uint256 sum;
        for (uint256 i; i < n; ++i) {
            uint128 amt = milestoneAmounts[i];
            if (amt == 0) revert ZeroAmount();
            sum += amt;
            _milestones[id].push(
                Milestone({ amount: amt, status: MilestoneStatus.Pending, disputedAt: 0 })
            );
        }
        if (sum != a.totalAmount) revert MilestoneSumMismatch();

        // Effects before the external transfer (CEI) + nonReentrant.
        resolutionPolicyOf[id] = policy;
        escrowedOf[id] = a.totalAmount;
        a.status = AgreementStatus.Funded;

        if (a.settlementAsset == address(0)) {
            if (msg.value != a.totalAmount) revert NativeValueMismatch();
        } else {
            if (msg.value != 0) revert NativeValueMismatch();
            IERC20 token = IERC20(a.settlementAsset);
            uint256 before = token.balanceOf(address(this));
            token.safeTransferFrom(msg.sender, address(this), a.totalAmount);
            // Fee-on-transfer / rebasing tokens are not supported: the escrow must receive
            // exactly what it accounts for, or conservation breaks. Fail closed.
            if (token.balanceOf(address(this)) - before != a.totalAmount) {
                revert UnsupportedTokenBehavior();
            }
        }

        emit AgreementFunded(id, a.totalAmount, n);
    }

    /// @notice Buyer approves the current milestone; the seller is credited its full
    ///         amount. Strictly in order.
    function approveMilestone(uint256 id, uint256 index) external nonReentrant {
        Agreement storage a = agreements[id];
        if (a.status != AgreementStatus.Funded) revert NotFunded();
        if (msg.sender != a.buyer) revert NotBuyer();
        Milestone storage m = _requireCurrentPending(id, index);

        _payoutAndAdvance(id, index, m.amount, 0, m.amount, MilestoneStatus.Released);
        emit MilestoneReleased(id, index, m.amount);
        _completeIfLast(id);
    }

    /// @notice Either party opens a dispute on the current milestone, starting the
    ///         evidence -> ruling -> timeout clock.
    function disputeMilestone(uint256 id, uint256 index) external {
        Agreement storage a = agreements[id];
        if (a.status != AgreementStatus.Funded) revert NotFunded();
        if (msg.sender != a.buyer && msg.sender != a.seller) revert NotParty();
        Milestone storage m = _requireCurrentPending(id, index);

        m.status = MilestoneStatus.Disputed;
        m.disputedAt = uint40(block.timestamp);
        emit MilestoneDisputed(id, index, msg.sender);
    }

    /// @notice The committed primary resolver rules a disputed milestone during the
    ///         ruling window. The core only ever learns a `buyerBps`; payouts go to the
    ///         buyer and seller only — never the resolver (whitepaper §4.2 rule 4).
    function rule(uint256 id, uint256 index, uint16 buyerBps) external nonReentrant {
        Agreement storage a = agreements[id];
        if (a.status != AgreementStatus.Funded) revert NotFunded();
        if (msg.sender != resolutionPolicyOf[id].primaryResolver) revert NotResolver();
        if (buyerBps > BPS_DENOMINATOR) revert BpsOutOfRange();
        Milestone storage m = _requireCurrentDisputed(id, index);

        (uint256 evidenceDeadline, uint256 rulingDeadline) = _deadlines(id, m.disputedAt);
        if (block.timestamp < evidenceDeadline) revert TooEarlyToRule();
        if (block.timestamp >= rulingDeadline) revert RulingWindowClosed();

        (uint128 buyerAmount, uint128 sellerAmount) = _split(m.amount, buyerBps);
        _payoutAndAdvance(id, index, m.amount, buyerAmount, sellerAmount, MilestoneStatus.Resolved);
        emit MilestoneRuled(id, index, buyerBps, buyerAmount, sellerAmount);
        _completeIfLast(id);
    }

    /// @notice Finalize a disputed milestone with the pre-committed timeout split once the
    ///         ruling deadline has lapsed with no ruling. Callable by ANYONE: liveness must
    ///         not depend on any particular party returning (whitepaper §4.3). The split is
    ///         the signed `timeoutBuyerBps`, so no admin invents it and no funds reach the
    ///         resolver.
    function finalizeTimeout(uint256 id, uint256 index) external nonReentrant {
        Agreement storage a = agreements[id];
        if (a.status != AgreementStatus.Funded) revert NotFunded();
        Milestone storage m = _requireCurrentDisputed(id, index);

        (, uint256 rulingDeadline) = _deadlines(id, m.disputedAt);
        if (block.timestamp < rulingDeadline) revert NotTimeoutEligible();

        uint16 timeoutBuyerBps = resolutionPolicyOf[id].timeoutBuyerBps;
        (uint128 buyerAmount, uint128 sellerAmount) = _split(m.amount, timeoutBuyerBps);
        _payoutAndAdvance(id, index, m.amount, buyerAmount, sellerAmount, MilestoneStatus.Resolved);
        emit MilestoneTimedOut(id, index, timeoutBuyerBps, buyerAmount, sellerAmount);
        _completeIfLast(id);
    }

    /// @notice Withdraw everything credited to the caller in `asset`. Pull payments keep a
    ///         hostile or contract recipient from ever blocking settlement for others.
    function withdraw(address asset) external nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender][asset];
        if (amount == 0) revert NothingToWithdraw();
        pendingWithdrawals[msg.sender][asset] = 0; // effects before interaction

        if (asset == address(0)) {
            (bool ok,) = msg.sender.call{ value: amount }("");
            if (!ok) revert NativeTransferFailed();
        } else {
            IERC20(asset).safeTransfer(msg.sender, amount);
        }
        emit Withdrawal(msg.sender, asset, amount);
    }

    // =====================================================================
    // Internal
    // =====================================================================

    function _structHash(AgreementIntent calldata intent) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                AGREEMENT_INTENT_TYPEHASH,
                intent.buyer,
                intent.seller,
                intent.settlementAsset,
                intent.totalAmount,
                intent.milestonesHash,
                intent.termsHash,
                intent.resolutionPolicyHash,
                intent.fundingDeadline,
                intent.executionDeadline,
                intent.nonce
            )
        );
    }

    function _validateDeadlines(uint64 fundingDeadline, uint64 executionDeadline) internal view {
        if (fundingDeadline != 0 && fundingDeadline <= block.timestamp) revert InvalidDeadlines();
        if (executionDeadline != 0) {
            uint64 lowerBound = fundingDeadline != 0 ? fundingDeadline : uint64(block.timestamp);
            if (executionDeadline <= lowerBound) revert InvalidDeadlines();
        }
    }

    function _validatePolicy(ResolutionPolicy calldata p, address buyer, address seller)
        internal
        pure
    {
        // Appeal is tranche C: reject any policy that asks for it so we never silently
        // accept an unenforceable appellate path.
        if (p.appellateResolver != address(0) || p.appealWindow != 0) {
            revert AppealNotSupportedYet();
        }
        if (
            p.primaryResolver == address(0) || p.primaryResolver == buyer
                || p.primaryResolver == seller
        ) {
            revert InvalidPolicy();
        }
        if (p.rulingWindow == 0 || p.rulingWindow > MAX_WINDOW || p.evidenceWindow > MAX_WINDOW) {
            revert InvalidPolicy();
        }
        if (p.timeoutBuyerBps > BPS_DENOMINATOR) revert InvalidPolicy();
    }

    function _requireCurrentPending(uint256 id, uint256 index)
        internal
        view
        returns (Milestone storage m)
    {
        if (index != nextMilestoneOf[id]) revert WrongMilestone();
        m = _milestones[id][index];
        if (m.status != MilestoneStatus.Pending) revert WrongMilestoneState();
    }

    function _requireCurrentDisputed(uint256 id, uint256 index)
        internal
        view
        returns (Milestone storage m)
    {
        if (index != nextMilestoneOf[id]) revert WrongMilestone();
        m = _milestones[id][index];
        if (m.status != MilestoneStatus.Disputed) revert WrongMilestoneState();
    }

    function _deadlines(uint256 id, uint40 disputedAt)
        internal
        view
        returns (uint256 evidenceDeadline, uint256 rulingDeadline)
    {
        ResolutionPolicy storage p = resolutionPolicyOf[id];
        evidenceDeadline = uint256(disputedAt) + p.evidenceWindow;
        rulingDeadline = evidenceDeadline + p.rulingWindow;
    }

    function _split(uint128 amount, uint16 buyerBps)
        internal
        pure
        returns (uint128 buyerAmount, uint128 sellerAmount)
    {
        buyerAmount = uint128((uint256(amount) * buyerBps) / BPS_DENOMINATOR);
        sellerAmount = amount - buyerAmount; // remainder to the seller; no unit is created or destroyed
    }

    /// @dev Credits the buyer/seller, marks the milestone settled, advances the pointer and
    ///      debits escrow. The sum of credits always equals `amount`, so escrow accounting
    ///      is exact (whitepaper §18 invariant 1).
    function _payoutAndAdvance(
        uint256 id,
        uint256 index,
        uint128 amount,
        uint128 buyerAmount,
        uint128 sellerAmount,
        MilestoneStatus newStatus
    ) internal {
        Agreement storage a = agreements[id];
        Milestone storage m = _milestones[id][index];

        m.status = newStatus;
        // index == nextMilestoneOf[id] (enforced by the require helpers), and the count is
        // bounded by MAX_MILESTONES, so this uint8 increment cannot overflow or skip.
        nextMilestoneOf[id] += 1;
        escrowedOf[id] -= amount;

        if (buyerAmount != 0) pendingWithdrawals[a.buyer][a.settlementAsset] += buyerAmount;
        if (sellerAmount != 0) pendingWithdrawals[a.seller][a.settlementAsset] += sellerAmount;
    }

    function _completeIfLast(uint256 id) internal {
        if (nextMilestoneOf[id] == _milestones[id].length) {
            agreements[id].status = AgreementStatus.Completed;
            emit AgreementCompleted(id);
        }
    }
}
