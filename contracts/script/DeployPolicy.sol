// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title DeployPolicy
/// @notice The safety rules both deployment scripts enforce, expressed as pure
///         logic with no environment access and no chain-state access.
/// @dev WHY THIS EXISTS
///
///      These guards were previously only reachable by executing
///      `DeployNexusEscrow.run()` / `DeployNexusEscrowBOT.run()`, which read
///      `vm.envUint` / `vm.envOr`. `forge coverage` reported 0% for both
///      scripts, so the "never deploy to mainnet by accident" control — the
///      single most consequential safety property of the deployment path — had
///      no automated proof at all.
///
///      Testing it through `run()` does not work. `vm.setEnv` mutates the real
///      PROCESS environment, which is global, not per-test: Foundry offers no
///      `unsetEnv`, parallel test threads race each other, and even serially a
///      value set by an earlier test leaks into later ones. Measured on a
///      24-core host: the same command produced 0, 1, 4, 8 and 10 failures on
///      consecutive runs. A safety test that is non-deterministic is worse than
///      no test, because it trains reviewers to ignore red.
///
///      So the decision logic lives here — `pure`, parameterised, no env — and
///      the scripts read the environment and delegate. The mainnet-gate revert
///      string is kept byte-identical to the original so the runbook and
///      `docs/evidence/mainnet-guard-677.log` remain accurate. The 968-pin
///      string was made script-neutral once a second script (Demo 1) began
///      sharing the guard; it is not captured by that evidence log.
library DeployPolicy {
    /// @dev Mainnet chain ids. Named constants, not literals, so the policy is
    ///      stated once.
    uint256 internal constant BOT_MAINNET_CHAIN_ID = 677;
    uint256 internal constant NEXUS_MAINNET_CHAIN_ID = 3946;
    uint256 internal constant BOT_TESTNET_CHAIN_ID = 968;

    string internal constant MAINNET_BLOCKED_MSG =
        "MAINNET DEPLOYMENT BLOCKED: set ALLOW_MAINNET_DEPLOYMENT=true only after independent security review";

    /// @notice True when `chainId` is a real-money network.
    function isMainnet(uint256 chainId) internal pure returns (bool) {
        return chainId == BOT_MAINNET_CHAIN_ID || chainId == NEXUS_MAINNET_CHAIN_ID;
    }

    /// @notice Enforces the mainnet opt-in for the chain-agnostic script.
    /// @dev Mainnet is refused unless the operator sets
    ///      `ALLOW_MAINNET_DEPLOYMENT=true` explicitly. Never the default.
    function requireMainnetOptIn(uint256 chainId, bool mainnetAllowed) internal pure {
        if (isMainnet(chainId) && !mainnetAllowed) {
            revert(MAINNET_BLOCKED_MSG);
        }
    }

    /// @notice Enforces the hard chain pin for the BOT-only wrapper scripts.
    /// @dev Deliberately ignores any mainnet opt-in: these scripts exist to
    ///      deploy to Bohr testnet 968 and nowhere else. Shared by both the
    ///      Demo 0 (`DeployNexusEscrowBOT`) and Demo 1 (`DeployNexEscrowCoreBOT`)
    ///      wrappers, so the revert names the policy, not a single script.
    function requireBotTestnetOnly(uint256 chainId) internal pure {
        if (chainId != BOT_TESTNET_CHAIN_ID) {
            revert("DeployPolicy: chain id must be 968 (BOT Chain Bohr testnet); aborting");
        }
    }

    /// @notice Rejects zero addresses before a contract is constructed.
    /// @dev Messages are parameters because the two scripts have always used
    ///      different wording, and operators grep the runbook for them.
    function requireNonZero(
        address owner,
        address feeRecipient,
        string memory ownerMsg,
        string memory feeRecipientMsg
    ) internal pure {
        if (owner == address(0)) {
            revert(ownerMsg);
        }
        if (feeRecipient == address(0)) {
            revert(feeRecipientMsg);
        }
    }
}
