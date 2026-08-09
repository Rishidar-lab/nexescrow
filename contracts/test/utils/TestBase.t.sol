// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { NexusEscrow } from "../../src/NexusEscrow.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";

abstract contract TestBase is Test {
    NexusEscrow internal escrow;
    MockERC20 internal token;

    address internal owner = makeAddr("owner");
    address internal feeRecipient = makeAddr("feeRecipient");
    address internal buyer = makeAddr("buyer");
    address internal seller = makeAddr("seller");
    address internal arbiter = makeAddr("arbiter");
    address internal stranger = makeAddr("stranger");

    function setUp() public virtual {
        escrow = new NexusEscrow(owner, feeRecipient);
        token = new MockERC20("Mock USD", "mUSD");

        vm.deal(buyer, 1_000 ether);
        token.mint(buyer, 1_000_000 ether);
    }

    function _singleMilestone(uint128 amount) internal pure returns (uint128[] memory m) {
        m = new uint128[](1);
        m[0] = amount;
    }

    function _threeMilestones() internal pure returns (uint128[] memory m) {
        m = new uint128[](3);
        m[0] = 1 ether;
        m[1] = 2 ether;
        m[2] = 3 ether;
    }

    function _sum(uint128[] memory amounts) internal pure returns (uint256 total) {
        for (uint256 i = 0; i < amounts.length; ++i) {
            total += amounts[i];
        }
    }

    function _createAgreement(address tokenAddr, uint128[] memory milestones, uint40 deadline)
        internal
        returns (uint256 id)
    {
        vm.prank(buyer);
        id = escrow.createAgreement(seller, arbiter, tokenAddr, milestones, deadline);
    }

    function _createNativeAgreement(uint128[] memory milestones) internal returns (uint256 id) {
        id = _createAgreement(address(0), milestones, 0);
    }

    function _createAndFundNative(uint128[] memory milestones) internal returns (uint256 id) {
        id = _createNativeAgreement(milestones);
        vm.prank(buyer);
        escrow.fund{ value: _sum(milestones) }(id);
    }

    function _createAndFundToken(uint128[] memory milestones) internal returns (uint256 id) {
        id = _createAgreement(address(token), milestones, 0);
        vm.startPrank(buyer);
        token.approve(address(escrow), _sum(milestones));
        escrow.fund(id);
        vm.stopPrank();
    }
}
