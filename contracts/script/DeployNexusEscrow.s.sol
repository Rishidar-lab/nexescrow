// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Script, console2 } from "forge-std/Script.sol";
import { NexusEscrow } from "../src/NexusEscrow.sol";

/// @notice Deploys NexusEscrow to whichever chain the RPC endpoint points at.
///         Owner/fee recipient default to the deployer if unset.
///
/// SAFETY GATES
///   - Mainnet chains (BOT 677, Nexus 3946) are REFUSED unless the operator sets
///     ALLOW_MAINNET_DEPLOYMENT=true explicitly. Never the default. Never do this
///     without an independent security review.
///   - The contract is unaudited; testnet first (BOT Bohr 968, Nexus testnet 3945).
///
/// Usage (BOT Bohr testnet 968):
///   forge script script/DeployNexusEscrow.s.sol:DeployNexusEscrow \
///     --rpc-url bot_testnet --broadcast \
///     --verify --verifier blockscout --verifier-url https://scan.bohr.life/api/ -vvvv
///
/// Usage (Nexus testnet 3945):
///   forge script script/DeployNexusEscrow.s.sol:DeployNexusEscrow \
///     --rpc-url nexus_testnet --broadcast \
///     --verify --verifier blockscout --verifier-url https://testnet.explorer.nexus.xyz/api/ -vvvv
///
/// See docs/DEPLOYMENT_RUNBOOK.md for the full procedure and rollback notes.
contract DeployNexusEscrow is Script {
    uint256 internal constant BOT_MAINNET_CHAIN_ID = 677;
    uint256 internal constant NEXUS_MAINNET_CHAIN_ID = 3946;

    function run() external returns (NexusEscrow escrow) {
        uint256 chainId = block.chainid;
        bool mainnetAllowed = vm.envOr("ALLOW_MAINNET_DEPLOYMENT", false);

        if (
            (chainId == BOT_MAINNET_CHAIN_ID || chainId == NEXUS_MAINNET_CHAIN_ID)
                && !mainnetAllowed
        ) {
            revert(
                "MAINNET DEPLOYMENT BLOCKED: set ALLOW_MAINNET_DEPLOYMENT=true only after independent security review"
            );
        }

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        address owner = vm.envOr("ESCROW_OWNER", deployer);
        address feeRecipient = vm.envOr("ESCROW_FEE_RECIPIENT", deployer);

        require(owner != address(0), "ESCROW_OWNER resolves to zero address");
        require(feeRecipient != address(0), "ESCROW_FEE_RECIPIENT resolves to zero address");

        console2.log("Chain ID:", chainId);
        console2.log("Deployer:", deployer);
        console2.log("Owner:", owner);
        console2.log("Fee recipient:", feeRecipient);
        if (chainId == BOT_MAINNET_CHAIN_ID) {
            console2.log("WARNING: BOT Chain MAINNET (677). Real funds. Unaudited.");
        } else if (chainId == NEXUS_MAINNET_CHAIN_ID) {
            console2.log("WARNING: Nexus MAINNET (3946). Real funds. Unaudited.");
        } else {
            console2.log("Testnet/non-mainnet deployment (good).");
        }

        vm.startBroadcast(deployerKey);
        escrow = new NexusEscrow(owner, feeRecipient);
        vm.stopBroadcast();

        console2.log("");
        console2.log("NexusEscrow deployed to:", address(escrow));
        console2.log("Next: set NEXT_PUBLIC_ESCROW_ADDRESS_%s in the frontend env", chainId);
        console2.log("      and NEXT_PUBLIC_DEPLOY_BLOCK_%s to the deployment block.", chainId);
        console2.log("Reminder: this contract is UNAUDITED. Do not present it as production ready.");
    }
}
