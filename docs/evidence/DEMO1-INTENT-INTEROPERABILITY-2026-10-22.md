# Demo 1 signed-intent interoperability — 2026-10-22

## Purpose

This increment adds deterministic, cross-language test vectors for the Demo 1 `NexEscrowCore` signing surface. It is intended to catch frontend/agent encoding drift before any Demo 1 deployment.

The canonical vector fixes the EIP-712 domain and agreement terms and requires Solidity and TypeScript/viem to agree on:

- `AgreementIntent` type hash;
- milestone-schedule commitment;
- resolution-policy commitment;
- EIP-712 domain separation; and
- final `AgreementIntent` digest.

Negative tests require the signed digest to change when the chain ID, verifying contract, or nonce changes.

## Evidence boundary

This is **code and local/CI test evidence only**.

It does **not** establish:

- a Demo 1 Bohr 968 deployment;
- BOT mainnet 677 compatibility or authorization;
- production indexer operation;
- independent security review or audit;
- external bug-bounty review; or
- production readiness.

The existing Bohr 968 deployment/evidence continues to describe Demo 0 only. No Demo 0 evidence file or deployed contract is modified by this increment.

BOT mainnet 677 remains disabled. This increment performs no network transaction, deployment, signing broadcast, RPC stress test, or mainnet access.

## Relationship to BOT network guidance

The interoperability vector is deliberately network-independent except for deterministic EIP-712 domain binding. It therefore does not attempt to answer the remaining BOT-owner questions concerning retry/backoff recommendations, reorganisation/finality or indexing-depth guidance beyond receipt confirmations, or specific Cancun opcode/precompile limitations.

Those remain separate network-policy gates.

## Review target

Review this increment as a narrow signing-boundary regression suite, not as a launch or deployment checkpoint.
