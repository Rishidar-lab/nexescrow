// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev ERC-20 with a configurable decimals value (0..18+). Escrow stores raw
///      units and must not assume 18 decimals anywhere.
contract MockDecimalsERC20 is ERC20 {
    uint8 private immutable DECIMALS;

    constructor(uint8 decimals_) ERC20("Decimal Token", "DEC") {
        DECIMALS = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return DECIMALS;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
