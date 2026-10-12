// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title INexEscrowMigrationReceiver
/// @notice A destination of a NexEscrow Demo 1 agreement migration (whitepaper §9). A funded
///         agreement's REMAINING principal and unsettled milestones are moved here atomically
///         after both parties sign the migration authorization. The receiver MUST return the
///         `onMigration.selector` magic value to confirm acceptance; any other return (or a
///         revert) aborts the migration and leaves the source agreement untouched.
/// @dev The source transfers the principal before calling (ERC-20) or along with the call
///      (native `msg.value`). The receiver must treat `legacyAgreementId` + the source
///      address as the provenance of the migrated agreement.
interface INexEscrowMigrationReceiver {
    function onMigration(
        uint256 legacyAgreementId,
        address buyer,
        address seller,
        address settlementAsset,
        uint256 remainingPrincipal,
        uint128[] calldata remainingMilestones
    ) external payable returns (bytes4);
}
