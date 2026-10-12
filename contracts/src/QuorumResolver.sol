// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { IResolver } from "./IResolver.sol";

/// @dev The subset of NexEscrowCore a resolver module needs to push a ruling.
interface INexEscrowCoreRuling {
    function rule(uint256 id, uint256 index, uint16 buyerBps) external;
    function finalRule(uint256 id, uint256 index, uint16 buyerBps) external;
}

/// @title QuorumResolver
/// @notice An M-of-N resolver module (whitepaper §5): a ruling is valid only with at least
///         `threshold` distinct member EIP-712 signatures over the exact (agreement,
///         milestone, buyerBps, isFinal) tuple. Members and threshold are fixed at
///         construction, so committing this contract's address in the signed
///         `ResolutionPolicy` commits the membership and threshold too — a quorum is a
///         policy, not an admin power (§5.2). Any caller may relay a sufficiently-signed
///         ruling; the quorum is over the signatures, not the relayer. This module holds
///         no funds and can only cause the core to split a disputed milestone between the
///         buyer and seller.
contract QuorumResolver is IResolver, EIP712 {
    address public immutable coreAddr;
    uint256 public immutable threshold;
    uint256 public immutable memberCount;
    mapping(address => bool) public isMember;

    bytes32 public constant RULING_TYPEHASH = keccak256(
        "Ruling(uint256 agreementId,uint256 milestoneIndex,uint16 buyerBps,bool isFinal)"
    );

    error ZeroCore();
    error ZeroMember();
    error BadThreshold();
    error DuplicateMember();
    error QuorumNotMet();
    error UnsortedOrDuplicateSigners();
    error SignerNotMember();

    constructor(address core_, address[] memory members_, uint256 threshold_)
        EIP712("NexEscrowQuorumResolver", "1")
    {
        if (core_ == address(0)) revert ZeroCore();
        uint256 n = members_.length;
        if (threshold_ == 0 || threshold_ > n) revert BadThreshold();
        for (uint256 i; i < n; ++i) {
            address mbr = members_[i];
            if (mbr == address(0)) revert ZeroMember();
            if (isMember[mbr]) revert DuplicateMember();
            isMember[mbr] = true;
        }
        coreAddr = core_;
        memberCount = n;
        threshold = threshold_;
    }

    /// @inheritdoc IResolver
    function core() external view returns (address) {
        return coreAddr;
    }

    /// @inheritdoc IResolver
    function resolverKind() external pure returns (string memory) {
        return "QuorumResolver";
    }

    /// @notice The EIP-712 digest members sign to authorize a ruling. `isFinal` separates a
    ///         primary ruling from an appellate one so a signature for one cannot be replayed
    ///         as the other.
    function hashRuling(uint256 id, uint256 index, uint16 buyerBps, bool isFinal)
        public
        view
        returns (bytes32)
    {
        return
            _hashTypedDataV4(keccak256(abi.encode(RULING_TYPEHASH, id, index, buyerBps, isFinal)));
    }

    /// @notice Relay a quorum-signed primary ruling to the core.
    function submitRuling(uint256 id, uint256 index, uint16 buyerBps, bytes[] calldata signatures)
        external
    {
        _verifyQuorum(id, index, buyerBps, false, signatures);
        INexEscrowCoreRuling(coreAddr).rule(id, index, buyerBps);
    }

    /// @notice Relay a quorum-signed appellate (final) ruling to the core.
    function submitFinalRuling(
        uint256 id,
        uint256 index,
        uint16 buyerBps,
        bytes[] calldata signatures
    ) external {
        _verifyQuorum(id, index, buyerBps, true, signatures);
        INexEscrowCoreRuling(coreAddr).finalRule(id, index, buyerBps);
    }

    /// @dev Requires at least `threshold` signatures, each from a distinct member. Signers
    ///      must be supplied in strictly ascending address order, which both enforces
    ///      distinctness cheaply and rejects a member being counted twice.
    function _verifyQuorum(
        uint256 id,
        uint256 index,
        uint16 buyerBps,
        bool isFinal,
        bytes[] calldata signatures
    ) internal view {
        if (signatures.length < threshold) revert QuorumNotMet();
        bytes32 digest = hashRuling(id, index, buyerBps, isFinal);
        address last = address(0);
        for (uint256 i; i < signatures.length; ++i) {
            address signer = ECDSA.recover(digest, signatures[i]);
            if (signer <= last) revert UnsortedOrDuplicateSigners();
            if (!isMember[signer]) revert SignerNotMember();
            last = signer;
        }
    }
}
