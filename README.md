<div align="center">

# NexEscrow

**Non-custodial, milestone-based escrow for on-chain agreements on Nexus L1.**

[![CI](https://github.com/Rishidar-lab/nexescrow/actions/workflows/ci.yml/badge.svg)](https://github.com/Rishidar-lab/nexescrow/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-0.8.26-363636?logo=solidity)](contracts/src/NexusEscrow.sol)
[![TypeScript](https://img.shields.io/badge/TypeScript-3178c6?style=flat-square&logo=typescript&logoColor=white)](frontend)

</div>

---

## Overview

Two parties agree on a milestone-based deliverable. The buyer locks funds (native NXS
or any ERC-20) into `NexusEscrow`; the seller gets paid out milestone by milestone as
the buyer approves each one. Neither party ever custodies the other's funds, and
neither can unilaterally seize them — if buyer and seller disagree on a milestone,
a third-party arbiter chosen at agreement creation splits that milestone's payout.

## Key features

- **Milestone-based release.** An agreement is a sequence of milestones, each released
  in order as the buyer approves it — not one all-or-nothing payout.
- **Arbitrated disputes, not unilateral timeouts.** Either party can dispute the current
  milestone; the arbiter then splits it by basis points between buyer and seller. There
  is deliberately no unilateral timeout-release — a ghosted counterparty is resolved by
  the arbiter, not a clock, which keeps the state machine small and removes a class of
  timeout-griefing attacks.
- **Native NXS or any ERC-20**, via `SafeERC20`.
- **Protocol fee**, in basis points, capped at 10% (`MAX_FEE_BPS`), snapshotted onto
  each agreement at creation time so a later fee change never affects agreements
  already in flight. Fee is only ever taken from the portion actually paid to the
  seller — a buyer refund is never taxed.

## Architecture / security notes

- **Contract:** `contracts/src/NexusEscrow.sol`. Single contract, agreements keyed by
  an incrementing `uint256` id, `ReentrancyGuard` + checks-effects-interactions on every
  fund-moving function, `Pausable` + `Ownable2Step` for admin controls. Not upgradeable
  by design — no proxy, no admin fund access beyond the fee split.
- **Test suite:** 57 Foundry tests across lifecycle, disputes, admin, and a dedicated
  security suite — including a reentrancy PoC (a malicious buyer contract that tries to
  reenter `approveMilestone` mid-payout, blocked by the shared `ReentrancyGuard` lock)
  and fuzz invariants (milestone sums always reconstitute the total; dispute splits
  always conserve buyer + seller + fee = milestone amount). See
  [`contracts/test/`](contracts/test).
- **Agreement discovery is log-based**, not an on-chain enumerable list — the frontend
  finds "your agreements" by scanning `AgreementCreated` events and filtering
  client-side. That's fine at testnet scale; a production deployment should back it
  with an indexer/subgraph instead of a full log scan (see
  [`frontend/src/hooks/useMyAgreements.ts`](frontend/src/hooks/useMyAgreements.ts)).
- **Audit status:** unaudited. This is a from-scratch rebuild, not yet reviewed by a
  third party — treat it as testnet/portfolio-grade until it has been.

## Quick start

### Prerequisites

- [Foundry](https://book.getfoundry.sh/) (`forge`, `cast`, `anvil`)
- Node.js ≥ 18, [pnpm](https://pnpm.io/)

### Contracts

```bash
cd contracts
pnpm install        # OpenZeppelin Contracts
forge test
```

See [`contracts/README.md`](contracts/README.md) for deploying to Nexus L1 testnet.

### Frontend

```bash
cd frontend
pnpm install
cp .env.example .env.local   # set the deployed contract address + RPC URL
pnpm dev
```

See [`frontend/README.md`](frontend/README.md) for the full env var list.

## Contributing & security

Found a vulnerability? Please don't open a public issue — reach out privately first.
For general contributions, open an issue to discuss the change before sending a PR.

## License

MIT — see [LICENSE](LICENSE).

---
*Built by [@parzival](https://github.com/Rishidar-lab) — security researcher & builder.*
