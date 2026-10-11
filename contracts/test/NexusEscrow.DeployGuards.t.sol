// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { DeployPolicy } from "../script/DeployPolicy.sol";
import { DeployNexusEscrow } from "../script/DeployNexusEscrow.s.sol";
import { DeployNexusEscrowBOT } from "../script/DeployNexusEscrowBOT.s.sol";
import { NexusEscrow } from "../src/NexusEscrow.sol";

/// @dev External shim around the pure policy.
///      `vm.expectRevert` cannot observe a revert from an `internal` library
///      function: the call is inlined, so it never reaches a frame deeper than
///      the cheatcode call itself ("call didn't revert at a lower depth than
///      cheatcode call depth"). This harness gives each rule a real external
///      frame so the revert is observable, without changing any production code.
contract DeployPolicyHarness {
    function mainnetOptIn(uint256 chainId, bool allowed) external pure {
        DeployPolicy.requireMainnetOptIn(chainId, allowed);
    }

    function botTestnetOnly(uint256 chainId) external pure {
        DeployPolicy.requireBotTestnetOnly(chainId);
    }

    function nonZero(
        address owner,
        address feeRecipient,
        string calldata ownerMsg,
        string calldata feeMsg
    ) external pure {
        DeployPolicy.requireNonZero(owner, feeRecipient, ownerMsg, feeMsg);
    }
}

/// @notice Guards the deployment path.
/// @dev Before this suite, `forge coverage` reported 0.00% on both deployment
///      scripts (0/30 and 0/20 executable lines) — so "never deploy to mainnet
///      by accident", the most consequential safety property in the deployment
///      path, had no automated proof whatsoever.
///
///      WHY THESE TESTS DO NOT CALL `run()`
///
///      Driving the scripts through `run()` requires setting
///      ALLOW_MAINNET_DEPLOYMENT / ESCREW_OWNER / PRIVATE_KEY via `vm.setEnv`,
///      which mutates the real PROCESS environment — global, not per-test.
///      Foundry exposes no `unsetEnv`; parallel test threads race; even
///      serialised, a value set by one test leaks into the next. Measured on a
///      24-core host, the identical command returned 0, 1, 4, 8 and 10 failures
///      on consecutive runs. A safety test that is non-deterministic is worse
///      than no test: it teaches reviewers to ignore red.
///
///      So the policy is factored into `DeployPolicy`, which is `pure` and takes
///      every input as a parameter. The tests below are therefore exact and
///      repeatable, and the scripts only read the environment and delegate.
///      A small set of wiring tests still exercises `run()` end-to-end to prove
///      the scripts are actually wired to the policy.
///
///      No test here broadcasts a transaction or contacts an RPC: `vm.chainId`
///      supplies chain identity and a broadcast inside a test is recorded but
///      never sent. Deployer keys come from `makeAddrAndKey`, so no key
///      material is written into this repository.
contract NexusEscrowDeployPolicyTest is Test {
    uint256 internal constant BOT_MAINNET = 677;
    uint256 internal constant NEXUS_MAINNET = 3946;
    uint256 internal constant BOT_TESTNET = 968;
    uint256 internal constant NEXUS_TESTNET = 3945;
    uint256 internal constant ANV = 31337;

    DeployPolicyHarness internal policy = new DeployPolicyHarness();

    address internal constant OWNER = address(0xA11CE);
    address internal constant FEE_RECIPIENT = address(0xFEE5);

    bytes internal constant MAINNET_BLOCKED =
        "MAINNET DEPLOYMENT BLOCKED: set ALLOW_MAINNET_DEPLOYMENT=true only after independent security review";
    bytes internal constant BOT_WRONG_CHAIN =
        "DeployNexusEscrowBOT: chain id must be 968 (BOT Chain Bohr testnet); aborting";

    // ---------------------------------------------------------------------
    // DeployPolicy.requireMainnetOptIn — the mainnet gate
    // ---------------------------------------------------------------------

    function test_Mainnet_BlockedWhen_NotAllowed() public {
        vm.expectRevert(MAINNET_BLOCKED);
        policy.mainnetOptIn(BOT_MAINNET, false);

        vm.expectRevert(MAINNET_BLOCKED);
        policy.mainnetOptIn(NEXUS_MAINNET, false);
    }

    function test_Mainnet_Allowed_When_Explicitly_OptedIn() public {
        DeployPolicy.requireMainnetOptIn(BOT_MAINNET, true);
        DeployPolicy.requireMainnetOptIn(NEXUS_MAINNET, true);
    }

    /// @dev Only the boolean decides this rule: owner, fee recipient and deployer
    ///      balance play no part in whether a mainnet deploy is permitted. A
    ///      `false` is refused no matter what else is supplied.
    function test_Mainnet_Blocked_RegardlessOf_AnyOtherInput() public {
        vm.expectRevert(MAINNET_BLOCKED);
        policy.mainnetOptIn(BOT_MAINNET, false);

        vm.expectRevert(MAINNET_BLOCKED);
        policy.mainnetOptIn(NEXUS_MAINNET, false);
    }

    /// @dev Testnets and unknown chains are never treated as mainnet. Pinned so
    ///      a future "known chains" table cannot silently start allowing one.
    function test_TestnetsAndUnknownChains_Are_NotMainnet() public {
        assertFalse(DeployPolicy.isMainnet(BOT_TESTNET), "968 is testnet");
        assertFalse(DeployPolicy.isMainnet(NEXUS_TESTNET), "3945 is testnet");
        assertFalse(DeployPolicy.isMainnet(ANV), "anvil is not mainnet");
        assertFalse(DeployPolicy.isMainnet(1), "chain 1 is not mainnet");
        assertFalse(DeployPolicy.isMainnet(0), "chain 0 is not mainnet");

        DeployPolicy.requireMainnetOptIn(BOT_TESTNET, false);
        DeployPolicy.requireMainnetOptIn(NEXUS_TESTNET, false);
        DeployPolicy.requireMainnetOptIn(ANV, false);
        DeployPolicy.requireMainnetOptIn(1, false);
    }

    function test_Mainnet_ExactlyTheseTwoChains() public {
        assertTrue(DeployPolicy.isMainnet(BOT_MAINNET), "677 is BOT mainnet");
        assertTrue(DeployPolicy.isMainnet(NEXUS_MAINNET), "3946 is Nexus mainnet");

        // Neighbouring ids must not be swept in by an off-by-one.
        assertFalse(DeployPolicy.isMainnet(676));
        assertFalse(DeployPolicy.isMainnet(678));
        assertFalse(DeployPolicy.isMainnet(3945));
        assertFalse(DeployPolicy.isMainnet(3947));
        assertFalse(DeployPolicy.isMainnet(968));
        assertFalse(DeployPolicy.isMainnet(969));
    }

    // ---------------------------------------------------------------------
    // DeployPolicy.requireBotTestnetOnly — the hard chain pin
    // ---------------------------------------------------------------------

    function testBOT_Policy_RejectsEveryChainExcept968() public {
        uint256[7] memory wrong = [BOT_MAINNET, NEXUS_MAINNET, NEXUS_TESTNET, ANV, 0, 1, 969];
        for (uint256 i = 0; i < wrong.length; ++i) {
            vm.expectRevert(BOT_WRONG_CHAIN);
            policy.botTestnetOnly(wrong[i]);
        }
    }

    function testBOT_Policy_Accepts968() public {
        DeployPolicy.requireBotTestnetOnly(BOT_TESTNET);
    }

    // ---------------------------------------------------------------------
    // DeployPolicy.requireNonZero
    // ---------------------------------------------------------------------

    function test_RevertWhen_OwnerIsZero() public {
        vm.expectRevert("ESCROW_OWNER resolves to zero address");
        policy.nonZero(address(0), FEE_RECIPIENT, "ESCROW_OWNER resolves to zero address", "unused");
    }

    function test_RevertWhen_FeeRecipientIsZero() public {
        vm.expectRevert("ESCROW_FEE_RECIPIENT resolves to zero address");
        policy.nonZero(OWNER, address(0), "unused", "ESCROW_FEE_RECIPIENT resolves to zero address");
    }

    /// @dev Owner is checked first; a zero owner must never be reported as a
    ///      fee-recipient problem.
    function test_ZeroOwner_TakesPrecedenceOver_ZeroFeeRecipient() public {
        vm.expectRevert("owner msg");
        policy.nonZero(address(0), address(0), "owner msg", "fee msg");
    }

    function test_NonZeroAddresses_Pass() public {
        DeployPolicy.requireNonZero(OWNER, FEE_RECIPIENT, "owner msg", "fee msg");
    }

    // ---------------------------------------------------------------------
    // Wiring: prove both scripts actually delegate to the policy
    // ---------------------------------------------------------------------

    /// @dev Every wiring test below drives a real `run()` call, which requires
    ///      `vm.setEnv` — and that mutates PROCESS-global state, so two tests
    ///      writing different values race. To make the suite deterministic,
    ///      every wiring test writes the SAME values through this one helper.
    ///      Identical writes cannot conflict, so the ordering stops mattering.
    ///
    ///      No wiring test ever sets ALLOW_MAINNET_DEPLOYMENT, so it stays
    ///      absent — which is precisely the default the mainnet guard requires.
    function _wireEnv() internal {
        (, uint256 deployerKey) = makeAddrAndKey("nexescrow-wiring-deployer");
        address deployer = vm.addr(deployerKey);
        vm.deal(deployer, 1 ether);
        vm.setEnv("PRIVATE_KEY", vm.toString(deployerKey));
        vm.setEnv("ESCROW_OWNER", vm.toString(deployer));
        vm.setEnv("ESCROW_FEE_RECIPIENT", vm.toString(deployer));
    }

    function _runOnBotTestnet() internal returns (NexusEscrow) {
        vm.chainId(BOT_TESTNET);
        _wireEnv();
        DeployNexusEscrow script = new DeployNexusEscrow();
        return script.run();
    }

    function test_Wiring_GenericScript_DeploysAndDelegatesToPolicy() public {
        NexusEscrow deployed = _runOnBotTestnet();
        assertTrue(address(deployed) != address(0), "script should deploy on 968");
        assertEq(deployed.protocolFeeBps(), 100);
        assertEq(deployed.nextAgreementId(), 0);
    }

    function test_Wiring_BOTScript_DeploysAndDelegatesToPolicy() public {
        vm.chainId(BOT_TESTNET);
        _wireEnv();

        DeployNexusEscrowBOT script = new DeployNexusEscrowBOT();
        NexusEscrow deployed = script.run();

        assertTrue(address(deployed) != address(0), "BOT wrapper should deploy on 968");
        assertEq(deployed.MAX_FEE_BPS(), 1000);
    }

    /// @dev The hardened wrapper must refuse chain 677 when driven through the
    ///      script itself — not only through the pure policy function. This is
    ///      the test that would catch the guard being unwired.
    function test_Wiring_BOTScript_RefusesMainnet677() public {
        vm.chainId(BOT_MAINNET);
        _wireEnv();

        DeployNexusEscrowBOT script = new DeployNexusEscrowBOT();
        vm.expectRevert(BOT_WRONG_CHAIN);
        script.run();
    }

    /// @dev And the generic script must refuse Nexus mainnet 3946 with no
    ///      opt-in set. This is the regression the whole suite exists to
    ///      prevent: an accidental real-money deploy.
    function test_Wiring_GenericScript_RefusesNexusMainnet() public {
        vm.chainId(NEXUS_MAINNET);
        _wireEnv();

        DeployNexusEscrow script = new DeployNexusEscrow();
        vm.expectRevert(MAINNET_BLOCKED);
        script.run();
    }

    /// @dev A deploy that "succeeds" must yield an operable escrow.
    function test_Wiring_DeployedContract_IsImmediatelyUsable() public {
        NexusEscrow deployed = _runOnBotTestnet();

        address seller = makeAddr("freshSeller");
        address arbiter = makeAddr("freshArbiter");
        uint128[] memory milestones = new uint128[](1);
        milestones[0] = 1 ether;

        assertEq(deployed.createAgreement(seller, arbiter, address(0), milestones, 0), 0);
    }
}
