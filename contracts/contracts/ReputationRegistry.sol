// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ReputationRegistry
 * @notice Tracks per-address settled escrow count and cumulative volume on Nexus L1.
 * @dev Only the registered Escrow contract may call recordSettlement.
 *      The escrow address is set once by the owner and is immutable thereafter.
 */
contract ReputationRegistry {

    // ─── Storage ─────────────────────────────────────────────────────────────

    address public owner;
    address public escrowContract;

    struct Reputation {
        uint256 settledCount;
        uint256 settledVolume; // cumulative NEX (wei)
    }

    mapping(address => Reputation) private _reputations;

    // Ordered list of addresses that have at least one settlement (for leaderboard)
    address[] public participants;
    mapping(address => bool) private _isParticipant;

    // ─── Events ──────────────────────────────────────────────────────────────

    event EscrowContractSet(address indexed escrowContract);
    event SettlementRecorded(
        address indexed payer,
        address indexed payee,
        uint256 amount,
        uint256 payerCount,
        uint256 payeeCount
    );

    // ─── Custom errors ───────────────────────────────────────────────────────

    error Unauthorized();
    error EscrowAlreadySet();
    error ZeroAddress();

    // ─── Constructor ─────────────────────────────────────────────────────────

    constructor() {
        owner = msg.sender;
    }

    // ─── Admin ───────────────────────────────────────────────────────────────

    /**
     * @notice Set the Escrow contract address. Can only be called once by the owner.
     */
    function setEscrowContract(address _escrowContract) external {
        if (msg.sender != owner)          revert Unauthorized();
        if (escrowContract != address(0)) revert EscrowAlreadySet();
        if (_escrowContract == address(0)) revert ZeroAddress();

        escrowContract = _escrowContract;
        emit EscrowContractSet(_escrowContract);
    }

    // ─── Restricted write ────────────────────────────────────────────────────

    /**
     * @notice Record a successful settlement. Restricted to the Escrow contract.
     * @param payer  Address that funded the escrow.
     * @param payee  Address that received the funds.
     * @param amount Amount of NEX (wei) settled.
     */
    function recordSettlement(address payer, address payee, uint256 amount) external {
        if (msg.sender != escrowContract) revert Unauthorized();

        _addParticipant(payer);
        _addParticipant(payee);

        _reputations[payer].settledCount  += 1;
        _reputations[payer].settledVolume += amount;

        _reputations[payee].settledCount  += 1;
        _reputations[payee].settledVolume += amount;

        emit SettlementRecorded(
            payer,
            payee,
            amount,
            _reputations[payer].settledCount,
            _reputations[payee].settledCount
        );
    }

    // ─── Public views ────────────────────────────────────────────────────────

    /**
     * @notice Get the reputation of an address.
     * @return count  Number of escrows settled.
     * @return volume Cumulative NEX volume (wei).
     */
    function reputationOf(address user)
        external
        view
        returns (uint256 count, uint256 volume)
    {
        Reputation storage r = _reputations[user];
        return (r.settledCount, r.settledVolume);
    }

    /**
     * @notice Total number of unique participants (for leaderboard pagination).
     */
    function participantCount() external view returns (uint256) {
        return participants.length;
    }

    /**
     * @notice Paginated leaderboard slice.
     * @param offset Starting index.
     * @param limit  Maximum entries to return.
     */
    function leaderboard(uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory addrs, uint256[] memory counts, uint256[] memory volumes)
    {
        uint256 total = participants.length;
        if (offset >= total) {
            return (new address[](0), new uint256[](0), new uint256[](0));
        }
        uint256 end = offset + limit;
        if (end > total) end = total;
        uint256 size = end - offset;

        addrs   = new address[](size);
        counts  = new uint256[](size);
        volumes = new uint256[](size);

        for (uint256 i = 0; i < size; i++) {
            address a = participants[offset + i];
            addrs[i]   = a;
            counts[i]  = _reputations[a].settledCount;
            volumes[i] = _reputations[a].settledVolume;
        }
    }

    // ─── Internal helpers ────────────────────────────────────────────────────

    function _addParticipant(address addr) internal {
        if (!_isParticipant[addr]) {
            _isParticipant[addr] = true;
            participants.push(addr);
        }
    }
}
