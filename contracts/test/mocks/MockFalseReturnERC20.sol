// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev ERC-20 whose transfer/transferFrom return `false` instead of reverting.
///      SafeERC20 must translate this into a revert, never a silent success.
contract MockFalseReturnERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function symbol() external pure returns (string memory) {
        return "FALSE";
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return false;
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return false;
    }
}
