// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { AgreementMetadataAdapter } from "./AgreementMetadataAdapter.sol";

/// @title X402Adapter
/// @notice Binds an x402 (HTTP-native payment) resource/payment descriptor to a NexEscrow
///         milestone (whitepaper §8.1). x402 and milestone escrow are NOT the same thing:
///         this records discovery/payment metadata only — it never settles, holds, or moves
///         funds. For immediate low-value API calls, x402 should remain direct settlement;
///         this adapter is for longer work where NexEscrow provides the conditional settlement.
contract X402Adapter is AgreementMetadataAdapter {
    struct Binding {
        bytes32 resourceHash; // hash of the x402 resource descriptor / PaymentRequired
        bytes32 paymentPayloadHash; // hash of the x402 payment payload / requirements
        bool set;
    }

    /// @dev agreementId => milestoneIndex => binding.
    mapping(uint256 => mapping(uint256 => Binding)) public bindings;

    event X402ResourceBound(
        uint256 indexed agreementId,
        uint256 indexed milestoneIndex,
        address indexed boundBy,
        bytes32 resourceHash,
        bytes32 paymentPayloadHash,
        string resourceURI
    );

    constructor(address escrow_) AgreementMetadataAdapter(escrow_) { }

    /// @notice Record an x402 resource/payment mapping for a milestone. Party-authenticated.
    function bindResource(
        uint256 agreementId,
        uint256 milestoneIndex,
        bytes32 resourceHash,
        bytes32 paymentPayloadHash,
        string calldata resourceURI
    ) external {
        _requireParty(agreementId);
        bindings[agreementId][milestoneIndex] = Binding(resourceHash, paymentPayloadHash, true);
        emit X402ResourceBound(
            agreementId, milestoneIndex, msg.sender, resourceHash, paymentPayloadHash, resourceURI
        );
    }
}
