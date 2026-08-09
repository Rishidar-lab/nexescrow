// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Script, console2 } from "forge-std/Script.sol";
import { NexusEscrow } from "../src/NexusEscrow.sol";

/// @notice Deploys NexusEscrow. Owner/fee recipient default to the deployer if unset.
///
/// Usage (see contracts/README.md for the full command, incl. Blockscout verification):
///   forge script script/DeployNexusEscrow.s.sol:DeployNexusEscrow \
///     --rpc-url nexus_testnet --broadcast --verify \
///     --verifier blockscout --verifier-url https://testnet.explorer.nexus.xyz/api/ -vvvv
contract DeployNexusEscrow is Script {
    function run() external returns (NexusEscrow escrow) {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        address owner = vm.envOr("ESCROW_OWNER", deployer);
        address feeRecipient = vm.envOr("ESCROW_FEE_RECIPIENT", deployer);

        vm.startBroadcast(deployerKey);
        escrow = new NexusEscrow(owner, feeRecipient);
        vm.stopBroadcast();

        console2.log("NexusEscrow deployed to:", address(escrow));
        console2.log("Owner:", owner);
        console2.log("Fee recipient:", feeRecipient);
    }
}
