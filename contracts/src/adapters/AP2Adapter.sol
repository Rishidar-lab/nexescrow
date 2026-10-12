// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { AgreementMetadataAdapter } from "./AgreementMetadataAdapter.sol";

/// @title AP2Adapter
/// @notice Binds AP2 (Agent Payments Protocol) Checkout/Payment Mandate hash references and
///         an optional receipt to a NexEscrow milestone (whitepaper §8.2). Only HASH
///         REFERENCES are stored, never full AP2 payloads, so a resolver can verify what the
///         user/agent was authorized to buy without the escrow core implementing AP2. This
///         adapter never moves funds.
contract AP2Adapter is AgreementMetadataAdapter {
    struct Binding {
        bytes32 checkoutMandateHash;
        bytes32 paymentMandateHash;
        bytes32 receiptHash; // optional (bytes32(0) if none)
        bool set;
    }

    /// @dev agreementId => milestoneIndex => binding.
    mapping(uint256 => mapping(uint256 => Binding)) public bindings;

    event AP2MandatesBound(
        uint256 indexed agreementId,
        uint256 indexed milestoneIndex,
        address indexed boundBy,
        bytes32 checkoutMandateHash,
        bytes32 paymentMandateHash,
        bytes32 receiptHash,
        string receiptURI
    );

    constructor(address escrow_) AgreementMetadataAdapter(escrow_) { }

    /// @notice Record AP2 mandate hashes (and an optional receipt) for a milestone, as
    ///         dispute evidence a resolver can later check. Party-authenticated.
    function bindMandates(
        uint256 agreementId,
        uint256 milestoneIndex,
        bytes32 checkoutMandateHash,
        bytes32 paymentMandateHash,
        bytes32 receiptHash,
        string calldata receiptURI
    ) external {
        _requireParty(agreementId);
        bindings[agreementId][milestoneIndex] =
            Binding(checkoutMandateHash, paymentMandateHash, receiptHash, true);
        emit AP2MandatesBound(
            agreementId,
            milestoneIndex,
            msg.sender,
            checkoutMandateHash,
            paymentMandateHash,
            receiptHash,
            receiptURI
        );
    }
}
