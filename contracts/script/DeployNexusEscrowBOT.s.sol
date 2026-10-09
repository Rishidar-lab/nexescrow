// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Script, console2 } from "forge-std/Script.sol";
import { NexusEscrow } from "../src/NexusEscrow.sol";

/// @notice Deploys NexusEscrow to BOT Chain Bohr testnet ONLY (chain id 968).
///
/// This script deliberately aborts on any other chain, including BOT mainnet 677.
/// It is used by scripts/deploy-bot-968.sh, which additionally verifies deployer
/// credentials, balance, predicts the contract address, and writes a manifest.
///
/// Usage (prefer the wrapper):
///   forge script script/DeployNexusEscrowBOT.s.sol:DeployNexusEscrowBOT \
///     --rpc-url bot_testnet --broadcast -vvvv
contract DeployNexusEscrowBOT is Script {
    uint256 internal constant BOT_TESTNET_CHAIN_ID = 968;

    function run() external returns (NexusEscrow escrow) {
        require(
            block.chainid == BOT_TESTNET_CHAIN_ID,
            "DeployNexusEscrowBOT: chain id must be 968 (BOT Chain Bohr testnet); aborting"
        );

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        require(deployer.balance > 0, "DeployNexusEscrowBOT: deployer has zero native balance");

        address owner = vm.envOr("ESCROW_OWNER", deployer);
        address feeRecipient = vm.envOr("ESCROW_FEE_RECIPIENT", deployer);
        require(owner != address(0), "DeployNexusEscrowBOT: ESCROW_OWNER resolves to zero");
        require(
            feeRecipient != address(0),
            "DeployNexusEscrowBOT: ESCROW_FEE_RECIPIENT resolves to zero"
        );

        console2.log("Chain ID:", block.chainid);
        console2.log("Deployer:", deployer);
        console2.log("Deployer balance (wei):", deployer.balance);
        console2.log("Owner:", owner);
        console2.log("Fee recipient:", feeRecipient);
        console2.log("Contract is UNAUDITED; testnet use only.");

        vm.startBroadcast(deployerKey);
        escrow = new NexusEscrow(owner, feeRecipient);
        vm.stopBroadcast();

        console2.log("NexusEscrow deployed to:", address(escrow));
        console2.log(
            "Set NEXT_PUBLIC_ESCROW_ADDRESS_968 and NEXT_PUBLIC_DEPLOY_BLOCK_968 in the frontend."
        );
    }
}
