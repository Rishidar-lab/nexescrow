// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./ReputationRegistry.sol";

/**
 * @title Escrow
 * @notice Verifiable escrow with optional arbiter and on-chain reputation tracking for Nexus L1 (NexusEVM).
 * @dev Uses checks-effects-interactions, ReentrancyGuard, custom errors, and block.timestamp for time.
 *      No tx.origin auth, no delegatecall, no string reverts.
 */
contract Escrow is ReentrancyGuard {

    // ─── State machine ───────────────────────────────────────────────────────

    enum State { Open, Funded, Released, Refunded, Disputed }

    struct EscrowInfo {
        address payer;
        address payee;
        address arbiter;   // address(0) means no arbiter
        uint256 amount;
        uint256 deadline;
        State   state;
    }

    // ─── Storage ─────────────────────────────────────────────────────────────

    ReputationRegistry public immutable reputationRegistry;
    uint256 public nextEscrowId = 1;
    mapping(uint256 => EscrowInfo) public escrows;

    // ─── Events ──────────────────────────────────────────────────────────────

    event EscrowCreated(
        uint256 indexed escrowId,
        address indexed payer,
        address indexed payee,
        address arbiter,
        uint256 deadline
    );
    event EscrowFunded(uint256 indexed escrowId, address indexed payer, uint256 amount);
    event EscrowReleased(uint256 indexed escrowId, address indexed payee, uint256 amount);
    event EscrowRefunded(uint256 indexed escrowId, address indexed payer, uint256 amount);
    event EscrowDisputed(uint256 indexed escrowId, address indexed disputer);

    // ─── Custom errors ───────────────────────────────────────────────────────

    error InvalidPayee();
    error InvalidDeadline();
    error InvalidAmount();
    error InvalidState();
    error Unauthorized();
    error NoArbiter();

    // ─── Constructor ─────────────────────────────────────────────────────────

    constructor(address _reputationRegistry) {
        reputationRegistry = ReputationRegistry(_reputationRegistry);
    }

    // ─── External functions ──────────────────────────────────────────────────

    /**
     * @notice Create a new escrow. Payer is msg.sender.
     * @param payee   Recipient of funds on release.
     * @param arbiter Optional dispute resolver; pass address(0) for none.
     * @param deadline Unix timestamp after which payer may unilaterally refund.
     * @return escrowId The new escrow identifier.
     */
    function createEscrow(
        address payee,
        address arbiter,
        uint256 deadline
    ) external returns (uint256 escrowId) {
        if (payee == address(0)) revert InvalidPayee();
        if (deadline <= block.timestamp) revert InvalidDeadline();

        escrowId = nextEscrowId++;

        escrows[escrowId] = EscrowInfo({
            payer:    msg.sender,
            payee:    payee,
            arbiter:  arbiter,
            amount:   0,
            deadline: deadline,
            state:    State.Open
        });

        emit EscrowCreated(escrowId, msg.sender, payee, arbiter, deadline);
    }

    /**
     * @notice Fund an Open escrow. Caller must be the payer.
     * @param escrowId Target escrow.
     */
    function fund(uint256 escrowId) external payable nonReentrant {
        EscrowInfo storage e = escrows[escrowId];

        if (e.state != State.Open)  revert InvalidState();
        if (msg.value == 0)         revert InvalidAmount();

        // Effects
        e.amount = msg.value;
        e.state  = State.Funded;

        emit EscrowFunded(escrowId, e.payer, msg.value);
    }

    /**
     * @notice Release funds to payee.
     *         Callable by payer (happy path) or arbiter (dispute resolution).
     *         During Disputed state only the arbiter may call.
     */
    function release(uint256 escrowId) external nonReentrant {
        EscrowInfo storage e = escrows[escrowId];

        if (e.state != State.Funded && e.state != State.Disputed) revert InvalidState();

        bool isPayer   = (msg.sender == e.payer);
        bool isArbiter = (msg.sender == e.arbiter);

        if (!isPayer && !isArbiter)                    revert Unauthorized();
        if (e.state == State.Disputed && !isArbiter)   revert Unauthorized();

        // Effects
        e.state = State.Released;
        uint256 amount = e.amount;

        // Interaction with registry (trusted internal call)
        reputationRegistry.recordSettlement(e.payer, e.payee, amount);

        // Interaction: transfer NEX to payee
        (bool ok, ) = e.payee.call{value: amount}("");
        require(ok, "Transfer failed");

        emit EscrowReleased(escrowId, e.payee, amount);
    }

    /**
     * @notice Refund NEX to payer.
     *         Callable by payer after deadline, or by arbiter at any time.
     *         During Disputed state only the arbiter may call.
     */
    function refund(uint256 escrowId) external nonReentrant {
        EscrowInfo storage e = escrows[escrowId];

        if (e.state != State.Funded && e.state != State.Disputed) revert InvalidState();

        bool isPayerAfterDeadline = (msg.sender == e.payer && block.timestamp >= e.deadline);
        bool isArbiter            = (msg.sender == e.arbiter);

        if (!isPayerAfterDeadline && !isArbiter)       revert Unauthorized();
        if (e.state == State.Disputed && !isArbiter)   revert Unauthorized();

        // Effects
        e.state = State.Refunded;
        uint256 amount = e.amount;

        // Interaction
        (bool ok, ) = e.payer.call{value: amount}("");
        require(ok, "Transfer failed");

        emit EscrowRefunded(escrowId, e.payer, amount);
    }

    /**
     * @notice Move a Funded escrow to Disputed state.
     *         Callable by payer or payee. Requires an arbiter to have been set.
     */
    function dispute(uint256 escrowId) external {
        EscrowInfo storage e = escrows[escrowId];

        if (e.state != State.Funded)                              revert InvalidState();
        if (e.arbiter == address(0))                              revert NoArbiter();
        if (msg.sender != e.payer && msg.sender != e.payee)      revert Unauthorized();

        e.state = State.Disputed;

        emit EscrowDisputed(escrowId, msg.sender);
    }
}
