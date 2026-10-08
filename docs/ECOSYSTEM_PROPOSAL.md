# Ecosystem Proposal — NexEscrow as Milestone Settlement Infrastructure

> **No fabricated traction.** This document contains no adoption, user, TVL, audit, or
> production claims because none exist. What exists is an open-source,
> test-covered, unaudited implementation and a concrete integration plan.

## 1. Positioning

NexEscrow is **non-custodial milestone settlement infrastructure**: a minimal,
deterministic escrow primitive that holds value and releases it against agreed
milestones, with human arbitration for disputes. It is not a marketplace, not a
custody service, and not an AI product. It is the settlement layer other products can
compose with.

## 2. Why a deterministic core

The escrow decides one thing: who gets which milestone's value, and when. Keeping that
core free of oracles, AI inference, upgrade hooks, and chain assumptions makes it
small enough to reason about, test exhaustively, and verify independently. Everything
that is not settlement — discovery, negotiation, automated evaluation, account
abstraction, gas sponsorship — belongs in layers around it.

## 3. Roadmap phases

Each phase is a target for product layers built **on top of** the same core; the core
does not change to accommodate them.

| Phase | Counterparties | Notes |
|---|---|---|
| **I — Human ↔ Human** | Two people, one agreement, one arbiter | Exactly what is implemented today. Testnet stage. |
| **II — Business ↔ Contractor** | Invoicing/milestone contracts | Needs identity/reputation and fiat off-ramps in surrounding products, not in the escrow. |
| **III — Human ↔ Agent** | A person hiring an autonomous service | The agent is a wallet; settlement stays deterministic. Any task-evaluation logic lives outside the core. |
| **IV — Agent ↔ Agent** | Two autonomous services | Requires machine-readable agreements and attestations in adapter layers; the escrow still just settles milestones. |

## 4. Explicit non-goals for the core contract

- No AI/ML inference, oracle calls, or nondeterminism in settlement.
- No ERC-4337/account-abstraction logic. Account abstraction, session keys, and gas
  sponsorship belong in a **future adapter layer** (a smart-account module that calls
  `createAgreement`/`fund`/`approveMilestone` as a normal address).
- No upgradeability, no admin principal access, no token issuance, no yield.
- No marketplace, matching, or reputation system.

## 5. What the current artifact offers an ecosystem like BOT Chain

- A small (≈6.3 KB runtime), dependency-light contract that settles native BOT or
  ERC-20 with no chain-specific assumptions.
- 112 passing Foundry tests including authorization matrices, token-edge cases, and a
  stateful invariant suite asserting solvency and state consistency.
- 98.6% line / 97.4% branch coverage of the contract; Slither clean at high/medium
  severity.
- A chain-agnostic frontend with fail-closed network handling and explicit
  TESTNET/UNAUDITED labelling — no silent mainnet behavior.
- Complete public documentation: threat model, arbitration model, funds flow,
  deployment runbook, indexing architecture, integration dossier.

## 6. What we would ask of BOT Chain (testnet stage)

1. Confirmation of EVM-hardfork compatibility (solc 0.8.26 / Cancun target).
2. Bohr testnet faucet access for a public deployment and a smoke-test lifecycle.
3. Explorer verification endpoint confirmation.
4. RPC `eth_getLogs` limits for the indexer/log-scan design.
5. Any ecosystem contract/verification conventions expected of integrators.

## 7. Success criteria for this integration phase

- A public BOT Bohr deployment with verified source and a documented lifecycle smoke
  test (not yet achieved — credentials/faucet pending).
- Indexer (or bounded log-scan) discovery working against the public deployment.
- No high/medium findings from an independent review before any mainnet discussion.
- Every claim in public materials matches on-chain reality; labels say `TESTNET /
  UNAUDITED` until they no longer apply.

## 8. Status statement

As of 2026-10-08: unaudited, no public deployment, no users, no TVL, no audit, no
partnerships. This proposal asks only for evaluation and testnet-stage support.
