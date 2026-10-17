// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev Contract that rejects all native transfers. Used as a seller to prove
///      native payout failure behaviour (release reverts; a 100% buyer refund
///      via arbitration never touches the rejecting receiver).
contract MockRejectingReceiver {
    receive() external payable {
        revert("no native");
    }
}
