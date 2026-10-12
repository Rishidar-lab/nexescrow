// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { SignatureChecker } from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

/// @title NexEscrowCore (Demo 1 — tranche A: signed bilateral intent)
/// @notice Demo 1 settlement kernel. This tranche implements ONLY the signed-intent
///         activation path: a bilateral EIP-712 `AgreementIntent`, signed by both the
///         buyer and the seller (an EOA via ECDSA or a smart account via EIP-1271), is
///         activated on-chain exactly once. Funding, in-order milestone release,
///         recoverable disputes with finite deadlines, resolver modules / quorum,
///         optional appeal, explicit migration and the agent adapters are later tranches
///         (docs/WHITEPAPER_DEMO_1.md §§4-9). The legacy Demo 0 contract `NexusEscrow`
///         is untouched and remains the only deployed instance.
/// @dev EIP-712 does not itself provide replay protection (whitepaper §7.2); this
///      contract consumes each intent's typed-data digest so the same intent can never
///      activate twice (invariant 7). Domain separation (chain id + verifying contract)
///      comes from OpenZeppelin `EIP712`, so an intent signed for one chain or contract
///      cannot activate on another (invariant 8). Both signatures go through
///      EIP-1271-aware validation, so contract-wallet validation failures are fail-closed
///      (invariant 9).
contract NexEscrowCore is EIP712 {
    // ---------------------------------------------------------------------
    // Types
    // ---------------------------------------------------------------------

    /// @dev `chainId` and `verifyingContract` are bound by the EIP-712 domain rather than
    ///      duplicated as struct fields: keeping them in the domain makes the domain the
    ///      single source of chain/contract separation and keeps the signed payload the
    ///      canonical terms only.
    struct AgreementIntent {
        address buyer;
        address seller;
        address settlementAsset; // address(0) == the chain's native asset
        uint256 totalAmount;
        bytes32 milestonesHash; // commitment to the ordered milestone schedule
        bytes32 termsHash; // commitment to the off-chain human-readable terms
        bytes32 resolutionPolicyHash; // commitment to the dispute/timeout policy (enforced in a later tranche)
        uint64 fundingDeadline; // 0 == no funding deadline
        uint64 executionDeadline; // 0 == no execution deadline
        uint256 nonce; // disambiguates otherwise-identical intents
    }

    enum AgreementStatus {
        None,
        Activated
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

    // ---------------------------------------------------------------------
    // Constants
    // ---------------------------------------------------------------------

    bytes32 public constant AGREEMENT_INTENT_TYPEHASH = keccak256(
        "AgreementIntent(address buyer,address seller,address settlementAsset,uint256 totalAmount,bytes32 milestonesHash,bytes32 termsHash,bytes32 resolutionPolicyHash,uint64 fundingDeadline,uint64 executionDeadline,uint256 nonce)"
    );

    // ---------------------------------------------------------------------
    // Storage
    // ---------------------------------------------------------------------

    uint256 public nextAgreementId;
    mapping(uint256 => Agreement) public agreements;
    /// @dev typed-data digest => activated. A consumed intent can never activate again.
    mapping(bytes32 => bool) public consumedIntent;

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    event AgreementActivated(
        uint256 indexed id,
        address indexed buyer,
        address indexed seller,
        bytes32 intentDigest,
        address settlementAsset,
        uint256 totalAmount,
        bytes32 milestonesHash
    );

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error ZeroBuyer();
    error ZeroSeller();
    error IdenticalParties();
    error ZeroAmount();
    error EmptyMilestonesHash();
    error InvalidDeadlines();
    error IntentAlreadyActivated();
    error InvalidBuyerSignature();
    error InvalidSellerSignature();

    constructor() EIP712("NexEscrowCore", "1") { }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    /// @notice EIP-712 typed-data digest for an intent, bound to this chain and contract.
    /// @dev Exposed so off-chain signers (wallets, the frontend, autonomous agents) and
    ///      tests derive the exact bytes to sign.
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

    // ---------------------------------------------------------------------
    // Activation
    // ---------------------------------------------------------------------

    /// @notice Activate a bilateral agreement from a doubly-signed EIP-712 intent.
    /// @dev Both signatures are checked with EIP-1271-aware validation, so EOAs (ECDSA)
    ///      and smart accounts are both supported and every validation failure is
    ///      fail-closed. The intent digest is consumed before the agreement is written;
    ///      there is no external interaction in this tranche, but consuming first keeps
    ///      the single-activation invariant intact once funding is added.
    /// @param intent The bilateral terms commitment.
    /// @param buyerSignature `intent.buyer`'s signature over `hashIntent(intent)`.
    /// @param sellerSignature `intent.seller`'s signature over `hashIntent(intent)`.
    /// @return id The newly activated agreement id.
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

        // Fail-closed: SignatureChecker returns false for a malformed signature, a wrong
        // signer, or an EIP-1271 wallet that does not return the magic value.
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

    // ---------------------------------------------------------------------
    // Internal
    // ---------------------------------------------------------------------

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

    /// @dev A set funding deadline must be in the future; a set execution deadline must
    ///      come strictly after the funding deadline (or after now, if funding has no
    ///      deadline). The committed timeout *disposition* is enforced in the funding /
    ///      dispute tranches; this only rejects nonsensical ordering at activation.
    function _validateDeadlines(uint64 fundingDeadline, uint64 executionDeadline) internal view {
        if (fundingDeadline != 0 && fundingDeadline <= block.timestamp) revert InvalidDeadlines();
        if (executionDeadline != 0) {
            uint64 lowerBound = fundingDeadline != 0 ? fundingDeadline : uint64(block.timestamp);
            if (executionDeadline <= lowerBound) revert InvalidDeadlines();
        }
    }
}
