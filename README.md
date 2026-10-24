<div align="center">

# NexEscrow

**Non-custodial, milestone-based escrow for on-chain agreements. Chain-agnostic.**

[![CI](https://github.com/Rishidar-lab/nexescrow/actions/workflows/ci.yml/badge.svg)](https://github.com/Rishidar-lab/nexescrow/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.26-363636?logo=solidity)](contracts/src/NexusEscrow.sol)
[![TypeScript](https://img.shields.io/badge/TypeScript-3178c6?style=flat-square&logo=typescript&logoColor=white)](frontend)

**Status: UNAUDITED · TESTNET STAGE · NOT PRODUCTION READY.** No independent audit has
been performed. Mainnet deployment is documented but opt-in and blocked by default.

</div>

---

## Repository layers: Demo 0 (deployed) and Demo 1 (hardening, in review)

This repository contains two settlement layers. **The Overview, features, test counts,
coverage, and Bohr evidence below describe Demo 0 unless stated otherwise.**

- **Demo 0 — `contracts/src/NexusEscrow.sol` (legacy baseline).** Single-arbiter
  milestone escrow. Deployed and lifecycle-validated on BOT Bohr testnet 968 (address
  under [Networks](#networks)); 130 Foundry tests. This is the only layer with on-chain
  deployment evidence.
- **Demo 1 — `contracts/src/NexEscrowCore.sol` + `QuorumResolver` + agent adapters
  (hardening, not yet deployed).** Adds bilateral EIP-712 signed intents (EIP-1271
  aware), recoverable disputes with finite evidence/ruling/appeal deadlines and a
  committed timeout disposition, an `IResolver` abstraction with an M-of-N quorum
  resolver, bilateral atomic migration (no owner principal sweep), x402/AP2/ERC-8004
  metadata adapters, and a production ingestion engine. Specified in
  [`docs/WHITEPAPER_DEMO_1.md`](docs/WHITEPAPER_DEMO_1.md); tracked in issue #3.

  **Demo 1 status: IMPLEMENTED + LOCAL/CI-TESTED only** (225 total Foundry tests incl.
  a handler-driven conservation-invariant suite; 60 frontend tests). It is **NOT
  deployed, NOT independently audited, and NOT production ready.** Per issue #3's
  evidence boundary, no Demo 1 item is "validated" until a fresh deployment and an
  independent review exist — Demo 0's Bohr evidence does **not** transfer to Demo 1.

## Overview

Two parties agree on a milestone-based deliverable. The buyer locks funds (the chain's
native asset or any supported ERC-20) into `NexusEscrow`; the seller is paid milestone
by milestone as the buyer approves each one. Neither party ever custodies the other's
funds, and neither can unilaterally seize them — if buyer and seller disagree on a
milestone, a third-party arbiter chosen at creation splits that milestone's payout.

The settlement core is chain-agnostic: no chain-id, native-symbol, or decimals
assumptions. A single frontend can target Nexus or BOT Chain, testnets by default.

## Key features

- **Milestone-based release.** Milestones release strictly in order as the buyer
  approves them — not one all-or-nothing payout.
- **Arbitrated disputes, not unilateral timeouts** *(Demo 0)*. Either party can dispute
  the current milestone; the arbiter splits it by basis points. No timeout-release by
  design (removes timeout-griefing; a silent arbiter is a disclosed liveness risk).
  *(Demo 1 instead adds a deterministic, pre-committed timeout disposition finalizable
  by anyone, so a silent arbiter cannot permanently freeze a milestone — see the
  whitepaper.)*
- **Native asset or ERC-20**, via `SafeERC20`. **Fee-on-transfer tokens are rejected at
  funding time** rather than silently under-collateralizing the agreement.
- **Protocol fee**, capped at 10%, snapshotted per agreement, charged only on the
  seller's side; buyer refunds are untaxed.
- **Non-upgradeable, no admin fund access.** No proxy, no `delegatecall`, no
  privileged path to escrow principal.
- **Fail-closed chain safety.** Frontend defaults to BOT Bohr testnet (968); mainnet
  requires explicit opt-in; every write asserts the wallet is on the selected chain.

## Architecture / security notes

- **Contract:** `contracts/src/NexusEscrow.sol` — single non-upgradeable contract,
  agreements keyed by incrementing ids, cursor-only milestone progression,
  `ReentrancyGuard` + checks-effects-interactions on every fund-moving function,
  `Pausable` + `Ownable2Step` for availability/fee admin only.
- **Tests:** 130 Foundry tests across 8 suites (lifecycle, disputes, admin, authorization
  matrix, deploy guards, token-edge cases, fuzz, and a handler-driven stateful invariant
  suite asserting exact solvency for native and ERC-20). 98.6% line / 97.4% branch
  coverage of `NexusEscrow` (Demo 0). Demo 1 (`NexEscrowCore` + resolvers + adapters)
  adds 95 further Foundry tests — 225 total — including its own handler-driven
  conservation-invariant suite; its evidence tier is tracked in issue #3.
- **Static analysis:** Slither 0.11.5 reports no high/medium findings; informational
  results are documented, not suppressed.
- **Agreement discovery:** bounded, chunked, deduped direct-RPC log scan by default,
  behind an index adapter; production ingestion spec in [`docs/INDEXING.md`](docs/INDEXING.md).
- **Audit status:** unaudited. See [`SECURITY.md`](SECURITY.md).

## Documentation

| Doc | Contents |
|---|---|
| [`docs/THREAT_MODEL.md`](docs/THREAT_MODEL.md) | Actors, state machines, function matrix, invariants, threat catalogue |
| [`docs/ARBITRATION_MODEL.md`](docs/ARBITRATION_MODEL.md) | Arbiter powers/limits, split math, trust assumptions |
| [`docs/TOKEN_AND_FUNDS_FLOW.md`](docs/TOKEN_AND_FUNDS_FLOW.md) | Asset flows, conservation, token support matrix |
| [`docs/BOTCHAIN_INTEGRATION.md`](docs/BOTCHAIN_INTEGRATION.md) | BOT Chain dossier: config, requirements, open questions, mainnet gates |
| [`docs/DEPLOYMENT_RUNBOOK.md`](docs/DEPLOYMENT_RUNBOOK.md) | Testnet-first deployment, guards, incident/rollback |
| [`docs/TESTNET_EVIDENCE.md`](docs/TESTNET_EVIDENCE.md) | Raw evidence log (local 968 lifecycle, guard proof, test/coverage runs) |
| [`docs/INDEXING.md`](docs/INDEXING.md) | Event identity and production indexing design |
| [`docs/ECOSYSTEM_PROPOSAL.md`](docs/ECOSYSTEM_PROPOSAL.md) | Positioning and phased roadmap (no fabricated traction) |
| [`SECURITY.md`](SECURITY.md) | Reporting policy and security guarantees |

## Networks

| | Chain ID | RPC | Explorer | Native |
|---|---|---|---|---|
| Nexus Testnet | `3945` | `https://testnet.rpc.nexus.xyz` | `https://testnet.explorer.nexus.xyz` | NEX |
| Nexus Mainnet | `3946` | `https://mainnet.rpc.nexus.xyz` | `https://explorer.nexus.xyz` | NEX |
| **BOT Chain Bohr (testnet)** | `968` | `https://rpc.bohr.life` | `https://scan.bohr.life` | BOT |
| BOT Chain Mainnet | `677` | `https://rpc.botchain.ai` | `https://scan.botchain.ai` | BOT |

BOT Bohr has a live, source-verified **unaudited testnet instance** at
[`0x6448…2700`](https://scan.bohr.life/address/0x6448668ae9cbbc41617c2bd5e4f29279320a2700)
(deployed and lifecycle-validated 2026-10-08; owned by discarded throwaway keys).
Mainnets are configured but **opt-in only**: the deploy script refuses them unless
`ALLOW_MAINNET_DEPLOYMENT=true`, and the frontend ignores mainnet selection unless
`NEXT_PUBLIC_ALLOW_MAINNET=true`. This repository has never been deployed to a mainnet.

## Quick start

### Contracts

```bash
cd contracts
pnpm install        # OpenZeppelin Contracts
forge test          # 130 tests; fuzz 1024 runs; invariants 128x64
forge fmt --check
```

Deploy to BOT Bohr testnet (968):

```bash
cp .env.example .env   # PRIVATE_KEY + optional ESCROW_OWNER/ESCROW_FEE_RECIPIENT
source .env
forge script script/DeployNexusEscrow.s.sol:DeployNexusEscrow \
  --rpc-url bot_testnet --broadcast \
  --verify --verifier blockscout --verifier-url https://scan.bohr.life/api/ -vvvv
```

### Frontend

```bash
cd frontend
pnpm install
cp .env.example .env.local   # NEXT_PUBLIC_CHAIN_ID + per-chain contract address
pnpm dev
```

## Contributing & security

Found a vulnerability? Report it privately — see [`SECURITY.md`](SECURITY.md). For
general contributions, open an issue to discuss the change before sending a PR.

## License

MIT — see [LICENSE](LICENSE).
