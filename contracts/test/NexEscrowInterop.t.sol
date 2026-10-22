// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { Test } from "forge-std/Test.sol";
import { NexEscrowCore } from "../src/NexEscrowCore.sol";

contract NexEscrowInteropTest is Test {
    NexEscrowCore internal core;

    address internal constant BUYER = 0x2222222222222222222222222222222222222222;
    address internal constant SELLER = 0x3333333333333333333333333333333333333333;
    address internal constant PRIMARY = 0x4444444444444444444444444444444444444444;
    address internal constant APPELLATE = 0x5555555555555555555555555555555555555555;

    bytes32 internal constant TERMS_HASH =
        0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb;
    bytes32 internal constant POLICY_DOCUMENT_HASH =
        0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa;

    bytes32 internal constant EXPECTED_TYPEHASH =
        0xfe390758628ab13972001fa41b34965f714e78e1ecbb1431320ce36bee75138f;
    bytes32 internal constant EXPECTED_MILESTONES_HASH =
        0x7fff640583561805cb1d4cec598e9ac6a95d2f28e1375b669d24543af54bffc9;
    bytes32 internal constant EXPECTED_POLICY_HASH =
        0x59d76a14039d4ce428d5c1a78306e83f0daf3f98208ac9cf9fc9a36746d41037;
    bytes32 internal constant EXPECTED_DOMAIN_SEPARATOR =
        0xa17e128ef9fc6a74ca4aa975cbfe70f4d36788c16e67c27f946008fab60613fe;
    bytes32 internal constant EXPECTED_INTENT_DIGEST =
        0xdc542fd1bf646bd77182b7d22f26386601bd7aca7db4ac6fc5761aaf2aff9e4c;

    function setUp() public {
        vm.chainId(968);
        // The cross-language vector fixes the verifying-contract address. `etch` installs
        // the runtime bytecode there so OZ EIP-712 derives the exact same domain separator.
        NexEscrowCore implementation = new NexEscrowCore();
        address vectorAddress = 0x1111111111111111111111111111111111111111;
        vm.etch(vectorAddress, address(implementation).code);
        core = NexEscrowCore(payable(vectorAddress));
    }

    function testCanonicalInteropVector() public view {
        uint128[] memory milestones = new uint128[](2);
        milestones[0] = 1 ether;
        milestones[1] = 2 ether;

        NexEscrowCore.ResolutionPolicy memory policy = NexEscrowCore.ResolutionPolicy({
            primaryResolver: PRIMARY,
            appellateResolver: APPELLATE,
            evidenceWindow: 3600,
            rulingWindow: 7200,
            appealWindow: 1800,
            timeoutBuyerBps: 4000,
            policyHash: POLICY_DOCUMENT_HASH
        });

        bytes32 milestonesHash = core.hashMilestones(milestones);
        bytes32 policyHash = core.hashPolicy(policy);
        assertEq(core.AGREEMENT_INTENT_TYPEHASH(), EXPECTED_TYPEHASH);
        assertEq(milestonesHash, EXPECTED_MILESTONES_HASH);
        assertEq(policyHash, EXPECTED_POLICY_HASH);
        assertEq(core.domainSeparator(), EXPECTED_DOMAIN_SEPARATOR);

        NexEscrowCore.AgreementIntent memory intent = NexEscrowCore.AgreementIntent({
            buyer: BUYER,
            seller: SELLER,
            settlementAsset: address(0),
            totalAmount: 3 ether,
            milestonesHash: milestonesHash,
            termsHash: TERMS_HASH,
            resolutionPolicyHash: policyHash,
            fundingDeadline: 1_800_000_000,
            executionDeadline: 1_800_100_000,
            nonce: 42
        });

        assertEq(core.hashIntent(intent), EXPECTED_INTENT_DIGEST);
    }

    function testDomainAndNonceSeparation() public {
        uint128[] memory milestones = new uint128[](2);
        milestones[0] = 1 ether;
        milestones[1] = 2 ether;

        NexEscrowCore.ResolutionPolicy memory policy = NexEscrowCore.ResolutionPolicy({
            primaryResolver: PRIMARY,
            appellateResolver: APPELLATE,
            evidenceWindow: 3600,
            rulingWindow: 7200,
            appealWindow: 1800,
            timeoutBuyerBps: 4000,
            policyHash: POLICY_DOCUMENT_HASH
        });

        NexEscrowCore.AgreementIntent memory intent = NexEscrowCore.AgreementIntent({
            buyer: BUYER,
            seller: SELLER,
            settlementAsset: address(0),
            totalAmount: 3 ether,
            milestonesHash: core.hashMilestones(milestones),
            termsHash: TERMS_HASH,
            resolutionPolicyHash: core.hashPolicy(policy),
            fundingDeadline: 1_800_000_000,
            executionDeadline: 1_800_100_000,
            nonce: 42
        });

        bytes32 canonical = core.hashIntent(intent);
        intent.nonce = 43;
        assertTrue(core.hashIntent(intent) != canonical);

        vm.chainId(969);
        assertTrue(core.hashIntent(intent) != canonical);
    }
}
