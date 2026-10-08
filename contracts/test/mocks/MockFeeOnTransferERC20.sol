// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Deflationary token: every transfer burns 1% of the sent amount, so the
///      recipient receives less than the sender sent. Used to prove the escrow
///      fails closed on `fund` rather than silently under-collateralizing.
contract MockFeeOnTransferERC20 is ERC20 {
    uint256 public constant FEE_BPS = 100; // 1%

    constructor() ERC20("Fee Token", "FEE") { }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0) && value > 0) {
            uint256 fee = (value * FEE_BPS) / 10_000;
            super._update(from, to, value - fee);
            if (fee > 0) super._update(from, address(0), fee);
        } else {
            super._update(from, to, value);
        }
    }
}
