// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { NexusEscrow } from "../../src/NexusEscrow.sol";

/// @dev ERC-20 that attempts to reenter the escrow from inside its own transfer
///      hooks. The target agreement id is configurable; the attack is armed once.
///      Proves every fund-moving escrow path shares the ReentrancyGuard lock.
contract MockReentrantERC20 is ERC20 {
    NexusEscrow public immutable ESCROW;
    uint256 public attackAgreementId;
    bool public armed;
    bool public attackAttempted;
    bool public reentryReverted;

    constructor(NexusEscrow escrow_) ERC20("Reentrant Token", "REENT") {
        ESCROW = escrow_;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function arm(uint256 agreementId) external {
        attackAgreementId = agreementId;
        armed = true;
        attackAttempted = false;
        reentryReverted = false;
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);
        if (armed && from != address(0) && to != address(0)) {
            armed = false;
            attackAttempted = true;
            try ESCROW.approveMilestone(attackAgreementId) {
                reentryReverted = false;
            } catch {
                reentryReverted = true;
            }
        }
    }
}
