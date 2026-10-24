// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Script, console2 } from "forge-std/Script.sol";
import { NexEscrowCore } from "../src/NexEscrowCore.sol";
import { QuorumResolver } from "../src/QuorumResolver.sol";
import { DeployPolicy } from "./DeployPolicy.sol";

/// @notice Deploys the Demo 1 settlement core (`NexEscrowCore`) — and, when
///         configured, one `QuorumResolver` bound to it — to BOT Chain Bohr
///         testnet ONLY (chain id 968).
///
/// This script deliberately aborts on any other chain, including BOT mainnet
/// 677, by delegating to the same tested `DeployPolicy.requireBotTestnetOnly`
/// guard the Demo 0 wrapper uses. It never references `ALLOW_MAINNET_DEPLOYMENT`:
/// refusing mainnet is this script's reason for existing.
///
/// `NexEscrowCore` has a zero-argument constructor (no owner, fee recipient,
/// admin, or pause — by design), so the core deployment takes no operator input
/// beyond a funded deployer key.
///
/// The resolver is OPTIONAL and entirely operator-governed:
///   - RESOLVER_MEMBERS   — comma-separated member addresses (the M-of-N set)
///   - RESOLVER_THRESHOLD — the M in M-of-N
/// If RESOLVER_MEMBERS is unset/empty, only the core is deployed and the
/// operator wires a resolver later. The member set and threshold are a
/// governance decision this script does not invent.
///
/// Usage (simulation only — NO --broadcast — to prove it compiles/plans):
///   forge script script/DeployNexEscrowCoreBOT.s.sol:DeployNexEscrowCoreBOT \
///     --rpc-url bot_testnet
/// To actually deploy (operator, with a funded 968 burner key in PRIVATE_KEY):
///   forge script script/DeployNexEscrowCoreBOT.s.sol:DeployNexEscrowCoreBOT \
///     --rpc-url bot_testnet --broadcast -vvvv
contract DeployNexEscrowCoreBOT is Script {
    function run() external returns (NexEscrowCore core, QuorumResolver resolver) {
        // Chain 968 and nothing else. Refuses BOT mainnet 677 and Nexus mainnet.
        DeployPolicy.requireBotTestnetOnly(block.chainid);

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        require(deployer.balance > 0, "DeployNexEscrowCoreBOT: deployer has zero native balance");

        console2.log("Chain ID:", block.chainid);
        console2.log("Deployer:", deployer);
        console2.log("Deployer balance (wei):", deployer.balance);
        console2.log("Contract is UNAUDITED; testnet use only.");

        vm.startBroadcast(deployerKey);

        core = new NexEscrowCore();
        console2.log("NexEscrowCore deployed to:", address(core));

        // Optional resolver: deployed only when a member set is supplied.
        address[] memory members = _optionalMembers();
        if (members.length > 0) {
            uint256 threshold = vm.envUint("RESOLVER_THRESHOLD");
            resolver = new QuorumResolver(address(core), members, threshold);
            console2.log("QuorumResolver deployed to:", address(resolver));
            console2.log("  bound core:", address(core));
            console2.log("  members:", members.length);
            console2.log("  threshold:", threshold);
        } else {
            console2.log("RESOLVER_MEMBERS unset: core deployed without a resolver.");
        }

        vm.stopBroadcast();

        console2.log(
            "Record the NexEscrowCore address + deploy block for the Demo 1 evidence package."
        );
    }

    /// @dev Reads RESOLVER_MEMBERS as a comma-separated address list, or returns
    ///      an empty array when unset/empty. Pure env plumbing; no chain access.
    function _optionalMembers() internal view returns (address[] memory) {
        try vm.envAddress("RESOLVER_MEMBERS", ",") returns (address[] memory m) {
            return m;
        } catch {
            return new address[](0);
        }
    }
}
