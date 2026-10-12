// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { AgreementMetadataAdapter } from "./AgreementMetadataAdapter.sol";

/// @title ERC8004Adapter
/// @notice EXPERIMENTAL — ERC-8004 (agent discovery / reputation / validation) is a Draft
///         ERC and must be treated as optional, not a production dependency (whitepaper §8.3).
///         This adapter references an agent registry/id + validation reference for an
///         agreement, and binds post-settlement feedback metadata to a milestone's evidence.
///         Payments are explicitly outside ERC-8004's scope; this adapter never moves funds.
contract ERC8004Adapter is AgreementMetadataAdapter {
    struct AgentRef {
        address agentRegistry;
        uint256 agentId;
        bytes32 validationRef; // validation request/response reference
        bool set;
    }

    /// @dev agreementId => agent reference (one agent identity per agreement).
    mapping(uint256 => AgentRef) public agentRefs;

    event AgentReferenceBound(
        uint256 indexed agreementId,
        address indexed boundBy,
        address agentRegistry,
        uint256 agentId,
        bytes32 validationRef
    );
    event FeedbackBound(
        uint256 indexed agreementId,
        uint256 indexed milestoneIndex,
        address indexed boundBy,
        bytes32 feedbackRef,
        bytes32 evidenceHash
    );

    constructor(address escrow_) AgreementMetadataAdapter(escrow_) { }

    /// @notice Reference an ERC-8004 agent identity + validation record for an agreement.
    function bindAgent(
        uint256 agreementId,
        address agentRegistry,
        uint256 agentId,
        bytes32 validationRef
    ) external {
        _requireParty(agreementId);
        agentRefs[agreementId] = AgentRef(agentRegistry, agentId, validationRef, true);
        emit AgentReferenceBound(agreementId, msg.sender, agentRegistry, agentId, validationRef);
    }

    /// @notice Bind post-settlement feedback/reputation metadata to a milestone's evidence.
    function bindFeedback(
        uint256 agreementId,
        uint256 milestoneIndex,
        bytes32 feedbackRef,
        bytes32 evidenceHash
    ) external {
        _requireParty(agreementId);
        emit FeedbackBound(agreementId, milestoneIndex, msg.sender, feedbackRef, evidenceHash);
    }
}
