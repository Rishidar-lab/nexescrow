// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { INexEscrowMigrationReceiver } from "../../src/INexEscrowMigrationReceiver.sol";

/// @notice A well-behaved migration destination: records what it received and returns the
///         magic selector so the source completes the migration.
contract MockMigrationReceiver is INexEscrowMigrationReceiver {
    uint256 public legacyId;
    address public rcvBuyer;
    address public rcvSeller;
    address public rcvAsset;
    uint256 public rcvPrincipal;
    uint256 public rcvValue;
    bool public called;
    uint128[] internal _rcvMilestones;

    function onMigration(
        uint256 id,
        address buyer,
        address seller,
        address asset,
        uint256 principal,
        uint128[] calldata milestones
    ) external payable returns (bytes4) {
        legacyId = id;
        rcvBuyer = buyer;
        rcvSeller = seller;
        rcvAsset = asset;
        rcvPrincipal = principal;
        rcvValue = msg.value;
        called = true;
        delete _rcvMilestones;
        for (uint256 i; i < milestones.length; ++i) {
            _rcvMilestones.push(milestones[i]);
        }
        return INexEscrowMigrationReceiver.onMigration.selector;
    }

    function rcvMilestones() external view returns (uint128[] memory) {
        return _rcvMilestones;
    }
}

/// @notice Returns the wrong magic value — the source must fail closed (MigrationRejected).
contract RejectingMigrationReceiver is INexEscrowMigrationReceiver {
    function onMigration(uint256, address, address, address, uint256, uint128[] calldata)
        external
        payable
        returns (bytes4)
    {
        return 0xdeadbeef;
    }
}

/// @notice Reverts — the whole migration must revert atomically.
contract RevertingMigrationReceiver is INexEscrowMigrationReceiver {
    error Nope();

    function onMigration(uint256, address, address, address, uint256, uint128[] calldata)
        external
        payable
        returns (bytes4)
    {
        revert Nope();
    }
}
