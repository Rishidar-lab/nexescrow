// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Ownable2Step, Ownable } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title NexusEscrow
/// @notice Non-custodial, milestone-based escrow for two-party agreements settled in
///         native NXS or any ERC-20 token, with third-party arbitration on disputes.
/// @dev Milestones for a given agreement release strictly in order. There is no
///      unilateral timeout release: a counterparty that goes unresponsive is handled
///      by raising a dispute and letting the designated arbiter decide, not by a clock.
///      This keeps the state machine small and avoids timeout-griefing attack surface.
contract NexusEscrow is ReentrancyGuard, Ownable2Step, Pausable {
    using SafeERC20 for IERC20;

    // ---------------------------------------------------------------------
    // Types
    // ---------------------------------------------------------------------

    enum MilestoneStatus {
        Pending,
        Released,
        Disputed,
        Resolved
    }

    enum AgreementStatus {
        AwaitingFunding,
        Active,
        Completed,
        Cancelled
    }

    struct Milestone {
        uint128 amount;
        MilestoneStatus status;
    }

    struct Agreement {
        address buyer;
        address seller;
        address arbiter;
        address token; // address(0) == native asset
        uint128 totalAmount;
        uint16 feeBps; // protocol fee snapshotted at creation time
        AgreementStatus status;
        uint40 createdAt;
        uint40 fundingDeadline; // 0 == no deadline
        uint8 milestoneCount;
        uint8 nextMilestone; // index of the next Pending/Disputed milestone
    }

    // ---------------------------------------------------------------------
    // Constants
    // ---------------------------------------------------------------------

    uint16 public constant MAX_FEE_BPS = 1_000; // 10% hard cap on protocol fee
    uint16 public constant BPS_DENOMINATOR = 10_000;
    uint8 public constant MAX_MILESTONES = 50;

    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    uint16 public protocolFeeBps = 100; // 1% default
    address public feeRecipient;

    uint256 public nextAgreementId;
    mapping(uint256 => Agreement) public agreements;
    mapping(uint256 => Milestone[]) internal _milestones;
    /// @dev token => amount owed to feeRecipient (address(0) == native)
    mapping(address => uint256) public accruedFees;

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event AgreementCreated(
        uint256 indexed id,
        address indexed buyer,
        address indexed seller,
        address arbiter,
        address token,
        uint128 totalAmount,
        uint16 feeBps,
        uint40 fundingDeadline,
        uint128[] milestoneAmounts
    );
    event Funded(uint256 indexed id);
    event MilestoneReleased(
        uint256 indexed id, uint256 indexed milestoneIndex, uint128 amount, uint128 fee
    );
    event DisputeRaised(
        uint256 indexed id, uint256 indexed milestoneIndex, address indexed raisedBy
    );
    event DisputeResolved(
        uint256 indexed id,
        uint256 indexed milestoneIndex,
        uint16 buyerBps,
        uint128 buyerAmount,
        uint128 sellerAmount,
        uint128 fee
    );
    event AgreementCancelled(uint256 indexed id);
    event AgreementCompleted(uint256 indexed id);
    event FeesWithdrawn(address indexed token, address indexed to, uint256 amount);
    event ProtocolFeeUpdated(uint16 oldBps, uint16 newBps);
    event FeeRecipientUpdated(address oldRecipient, address newRecipient);

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error InvalidAddress();
    error InvalidMilestones();
    error InvalidAmount();
    error FeeTooHigh();
    error BpsOutOfRange();
    error NotBuyer();
    error NotArbiter();
    error NotParty();
    error NotAuthorized();
    error WrongState();
    error WrongMilestoneState();
    error DeadlinePassed();
    error NativeValueMismatch();
    error NothingToWithdraw();
    error NativeTransferFailed();

    // ---------------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------------

    constructor(address initialOwner, address initialFeeRecipient) Ownable(initialOwner) {
        if (initialFeeRecipient == address(0)) revert InvalidAddress();
        feeRecipient = initialFeeRecipient;
    }

    // ---------------------------------------------------------------------
    // Modifiers
    // ---------------------------------------------------------------------

    modifier onlyBuyerOf(uint256 id) {
        _checkBuyer(id);
        _;
    }

    modifier onlyArbiterOf(uint256 id) {
        _checkArbiter(id);
        _;
    }

    function _checkBuyer(uint256 id) internal view {
        if (msg.sender != agreements[id].buyer) revert NotBuyer();
    }

    function _checkArbiter(uint256 id) internal view {
        if (msg.sender != agreements[id].arbiter) revert NotArbiter();
    }

    // ---------------------------------------------------------------------
    // Agreement lifecycle
    // ---------------------------------------------------------------------

    /// @notice Creates a new escrow agreement. Caller becomes the buyer.
    /// @param seller Counterparty receiving milestone payouts.
    /// @param arbiter Neutral third party who resolves disputes for this agreement.
    /// @param token ERC-20 token address, or address(0) for native NXS.
    /// @param milestoneAmounts Ordered milestone payout amounts; must sum to the total.
    /// @param fundingDeadline Unix timestamp by which the buyer must call `fund`, or 0 for none.
    function createAgreement(
        address seller,
        address arbiter,
        address token,
        uint128[] calldata milestoneAmounts,
        uint40 fundingDeadline
    ) external whenNotPaused returns (uint256 id) {
        if (seller == address(0) || seller == msg.sender) {
            revert InvalidAddress();
        }
        if (arbiter == address(0) || arbiter == msg.sender || arbiter == seller) {
            revert InvalidAddress();
        }

        uint256 count = milestoneAmounts.length;
        if (count == 0 || count > MAX_MILESTONES) revert InvalidMilestones();

        uint256 total;
        for (uint256 i = 0; i < count; ++i) {
            uint128 amount = milestoneAmounts[i];
            if (amount == 0) revert InvalidAmount();
            total += amount;
        }
        if (total > type(uint128).max) revert InvalidAmount();
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 totalAmount = uint128(total); // safe: bounded by the check above

        if (fundingDeadline != 0 && fundingDeadline <= block.timestamp) revert DeadlinePassed();

        id = nextAgreementId++;

        Agreement storage a = agreements[id];
        a.buyer = msg.sender;
        a.seller = seller;
        a.arbiter = arbiter;
        a.token = token;
        a.totalAmount = totalAmount;
        a.feeBps = protocolFeeBps;
        a.status = AgreementStatus.AwaitingFunding;
        a.createdAt = uint40(block.timestamp);
        a.fundingDeadline = fundingDeadline;
        // forge-lint: disable-next-line(unsafe-typecast)
        a.milestoneCount = uint8(count); // safe: count <= MAX_MILESTONES (50)

        Milestone[] storage milestones = _milestones[id];
        for (uint256 i = 0; i < count; ++i) {
            milestones.push(
                Milestone({ amount: milestoneAmounts[i], status: MilestoneStatus.Pending })
            );
        }

        emit AgreementCreated(
            id,
            msg.sender,
            seller,
            arbiter,
            token,
            totalAmount,
            protocolFeeBps,
            fundingDeadline,
            milestoneAmounts
        );
    }

    /// @notice Buyer deposits the full agreement amount, activating it.
    function fund(uint256 id) external payable nonReentrant whenNotPaused onlyBuyerOf(id) {
        Agreement storage a = agreements[id];
        if (a.status != AgreementStatus.AwaitingFunding) revert WrongState();
        if (a.fundingDeadline != 0 && block.timestamp > a.fundingDeadline) revert DeadlinePassed();

        a.status = AgreementStatus.Active;

        if (a.token == address(0)) {
            if (msg.value != a.totalAmount) revert NativeValueMismatch();
        } else {
            if (msg.value != 0) revert NativeValueMismatch();
            IERC20(a.token).safeTransferFrom(msg.sender, address(this), a.totalAmount);
        }

        emit Funded(id);
    }

    /// @notice Buyer approves the current pending milestone, releasing its payout to the seller.
    function approveMilestone(uint256 id) external nonReentrant whenNotPaused onlyBuyerOf(id) {
        Agreement storage a = agreements[id];
        if (a.status != AgreementStatus.Active) revert WrongState();

        uint8 idx = a.nextMilestone;
        Milestone storage m = _milestones[id][idx];
        if (m.status != MilestoneStatus.Pending) revert WrongMilestoneState();

        m.status = MilestoneStatus.Released;
        _advance(a, id);

        uint128 amount = m.amount;
        uint128 fee = uint128((uint256(amount) * a.feeBps) / BPS_DENOMINATOR);
        uint128 sellerAmount = amount - fee;

        if (fee > 0) accruedFees[a.token] += fee;
        _payOut(a.token, a.seller, sellerAmount);

        emit MilestoneReleased(id, idx, amount, fee);
    }

    /// @notice Either party disputes the current pending milestone, freezing it for arbitration.
    function raiseDispute(uint256 id) external whenNotPaused {
        Agreement storage a = agreements[id];
        if (a.status != AgreementStatus.Active) revert WrongState();
        if (msg.sender != a.buyer && msg.sender != a.seller) revert NotParty();

        uint8 idx = a.nextMilestone;
        Milestone storage m = _milestones[id][idx];
        if (m.status != MilestoneStatus.Pending) revert WrongMilestoneState();

        m.status = MilestoneStatus.Disputed;
        emit DisputeRaised(id, idx, msg.sender);
    }

    /// @notice Arbiter resolves the disputed milestone, splitting it between buyer and seller.
    /// @param buyerBps Share (in basis points) of the milestone refunded to the buyer;
    ///                 the remainder, minus the protocol fee, goes to the seller.
    function resolveDispute(uint256 id, uint16 buyerBps)
        external
        nonReentrant
        whenNotPaused
        onlyArbiterOf(id)
    {
        if (buyerBps > BPS_DENOMINATOR) revert BpsOutOfRange();

        Agreement storage a = agreements[id];
        if (a.status != AgreementStatus.Active) revert WrongState();

        uint8 idx = a.nextMilestone;
        Milestone storage m = _milestones[id][idx];
        if (m.status != MilestoneStatus.Disputed) revert WrongMilestoneState();

        m.status = MilestoneStatus.Resolved;
        _advance(a, id);

        uint128 amount = m.amount;
        uint128 buyerAmount = uint128((uint256(amount) * buyerBps) / BPS_DENOMINATOR);
        uint128 sellerGross = amount - buyerAmount;
        uint128 fee = uint128((uint256(sellerGross) * a.feeBps) / BPS_DENOMINATOR);
        uint128 sellerAmount = sellerGross - fee;

        if (fee > 0) accruedFees[a.token] += fee;
        if (buyerAmount > 0) _payOut(a.token, a.buyer, buyerAmount);
        if (sellerAmount > 0) _payOut(a.token, a.seller, sellerAmount);

        emit DisputeResolved(id, idx, buyerBps, buyerAmount, sellerAmount, fee);
    }

    /// @notice Cancels an unfunded agreement. Callable by either party at any time, or by
    ///         anyone once the funding deadline has passed.
    function cancelBeforeFunding(uint256 id) external whenNotPaused {
        Agreement storage a = agreements[id];
        if (a.status != AgreementStatus.AwaitingFunding) revert WrongState();

        bool isParty = msg.sender == a.buyer || msg.sender == a.seller;
        bool deadlinePassed = a.fundingDeadline != 0 && block.timestamp > a.fundingDeadline;
        if (!isParty && !deadlinePassed) revert NotAuthorized();

        a.status = AgreementStatus.Cancelled;
        emit AgreementCancelled(id);
    }

    // ---------------------------------------------------------------------
    // Fees
    // ---------------------------------------------------------------------

    /// @notice Sends accrued protocol fees for a token to the fee recipient.
    function withdrawFees(address token) external nonReentrant {
        if (msg.sender != feeRecipient) revert NotAuthorized();

        uint256 amount = accruedFees[token];
        if (amount == 0) revert NothingToWithdraw();
        accruedFees[token] = 0;

        _payOut(token, feeRecipient, amount);
        emit FeesWithdrawn(token, feeRecipient, amount);
    }

    function setProtocolFee(uint16 bps) external onlyOwner {
        if (bps > MAX_FEE_BPS) revert FeeTooHigh();
        emit ProtocolFeeUpdated(protocolFeeBps, bps);
        protocolFeeBps = bps;
    }

    function setFeeRecipient(address recipient) external onlyOwner {
        if (recipient == address(0)) revert InvalidAddress();
        emit FeeRecipientUpdated(feeRecipient, recipient);
        feeRecipient = recipient;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    function getMilestones(uint256 id) external view returns (Milestone[] memory) {
        return _milestones[id];
    }

    function getMilestone(uint256 id, uint256 index) external view returns (Milestone memory) {
        return _milestones[id][index];
    }

    // ---------------------------------------------------------------------
    // Internal helpers
    // ---------------------------------------------------------------------

    function _advance(Agreement storage a, uint256 id) internal {
        uint8 next = a.nextMilestone + 1;
        a.nextMilestone = next;
        if (next == a.milestoneCount) {
            a.status = AgreementStatus.Completed;
            emit AgreementCompleted(id);
        }
    }

    function _payOut(address token, address to, uint256 amount) internal {
        if (amount == 0) return;
        if (token == address(0)) {
            (bool ok,) = payable(to).call{ value: amount }("");
            if (!ok) revert NativeTransferFailed();
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }
}
