// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice The read-only surface a metadata adapter needs from NexEscrowCore.
interface INexEscrowView {
    function partiesOf(uint256 id)
        external
        view
        returns (address buyer, address seller, uint8 status);
}

/// @title AgreementMetadataAdapter
/// @notice Base for NexEscrow Demo 1 agent-interop adapters (whitepaper §8). Adapters bind
///         external protocol metadata (x402 / AP2 / ERC-8004) to an existing agreement so a
///         resolver or counterparty can later verify what was authorized — WITHOUT the
///         settlement core depending on any of those schemas.
/// @dev Invariant 10: an adapter never moves principal. These contracts are payable-free,
///      hold no funds, and only ever *read* the core (`partiesOf`). Settlement happens
///      solely through NexEscrowCore's own party/resolver-authorized transitions. Adapters
///      are independently deployable and versioned (§8.4), so protocol churn never forces a
///      core redeployment.
abstract contract AgreementMetadataAdapter {
    INexEscrowView public immutable escrow;

    error ZeroEscrow();
    error UnknownAgreement();
    error NotParty();

    constructor(address escrow_) {
        if (escrow_ == address(0)) revert ZeroEscrow();
        escrow = INexEscrowView(escrow_);
    }

    /// @dev Only a party (buyer or seller) of an existing agreement may bind metadata to it.
    ///      `status == 0` is `AgreementStatus.None`, i.e. the agreement does not exist.
    function _requireParty(uint256 id) internal view {
        (address buyer, address seller, uint8 status) = escrow.partiesOf(id);
        if (status == 0) revert UnknownAgreement();
        if (msg.sender != buyer && msg.sender != seller) revert NotParty();
    }
}
