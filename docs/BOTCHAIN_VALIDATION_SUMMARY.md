# NexEscrow x BOT Chain Validation Summary

## Status

**BOT TESTNET VALIDATED** - unaudited, testnet only, no production-readiness claim.

## Network

- BOT Chain Bohr Testnet, Chain ID `968`
- RPC: `https://rpc.bohr.life`
- Explorer: `https://scan.bohr.life`

## Source

- Repository: `Rishidar-lab/nexescrow`
- Branch: `feat/botchain-integration`
- Validation evidence commit: `bd13aae78b9e602fb83e7486a62b44708ec00843`
  (later packaging commits may add docs/tooling on top; the evidence commit is immutable)
- Evidence directory: `docs/evidence/bot-968/`
- Reproducible verifier: `scripts/verify-bot-968-evidence.py`
  (`python3 scripts/verify-bot-968-evidence.py --rpc-url https://rpc.bohr.life`)

## Contract

| Item | Value |
|---|---|
| Address | `0x6448668ae9cbbc41617c2bd5e4f29279320a2700` |
| Deployment tx | `0x4216d1e1eb33e296e3a3040baa723b507ce2da449d60e6ffe9456cecacf6da61` |
| Deployment block | `26178651` |
| Bytecode hash (runtime) | `0x7fba19dd52ec2caff42086cc4af9f342caed5564fc1240557e779e1353ea59a7` |
| Explorer | https://scan.bohr.life/address/0x6448668ae9cbbc41617c2bd5e4f29279320a2700 |
| Verification | **Verified** (`is_verified: true`), solc `v0.8.26+commit.8a97fa7a`, optimizer on, `evm_version: cancun`, verified `2026-10-08T21:05:40Z` |
| Owner | throwaway key generated for the run and intentionally discarded (admin functions inert); this instance is a validation artifact, not a service |

## Validation

Normal lifecycle (agreement 0):

| Step | Tx |
|---|---|
| createAgreement | `0xf9f4b64cfd8c7e4f0270889800c15efb9ee6fa66e2622fff495ddb4053d78608` |
| fund 0.1 BOT | `0xe52792a7054cbfc6b3f74e982e340865109f7417054427e42ca7ba4bf7760a1d` |
| approveMilestone 0 | `0x42bcb8608046d459afcdafc6e2909e7e478d3d0db1c07f97781fbfac43ef746e` |
| approveMilestone 1 | `0xba6e78551f8d0a27529b87f62de6b440f9d442f940f519d92ea110fc137c39b1` |

Result: 2/2 milestones `Released`, agreement `Completed`.

Dispute lifecycle (agreement 1):

| Step | Tx |
|---|---|
| createAgreement | `0x1b49e4e23cd81cc8e970468a9934a46fdb67072f89d834a6c9935f0e4c36d560` |
| fund 0.1 BOT | `0xb8115ec9c424788564b2259ccfe91c0c1a5d92db9911fda86c49d681ba2774fb` |
| raiseDispute (seller) | `0x37275e2a1fa60c2021159b3d7294e961024c2236e080eb889bcd82e1334009bd` |
| resolveDispute(6000) (arbiter) | `0x3a53ede3d28fc1a3700d3a7ee2a87df0c465acf832a542dbe5e325bdf3aa2221` |

Result: milestone `Resolved`, agreement `Completed`; split exact
(buyer `0.06 BOT`, seller `0.0396 BOT`, fee `0.0004 BOT`).

Other validation evidence:

- **Event retrieval:** 11 logs; the event identity set
  `(chainId, contractAddress, txHash, logIndex)` was re-queried read-only and matches
  the committed `events.json` exactly.
- **Event-vs-direct-state reconciliation:** event-derived state equals direct contract
  reads (ids, cursor, statuses, amounts, fees).
- **Frontend/network controls:** testnet default (968), mainnet opt-in only,
  wrong-network writes blocked, per-chain contract addresses; 4/4 chain-safety
  assertions pass in CI.
- **RPC capability:** full matrix in `docs/evidence/bot-rpc-capability.md`.

## Asset conservation

Exact, gas-independent:

```
funded total         0.2 BOT   (0.1 + 0.1)
released gross       0.1 BOT   (agreement 0: 0.05 + 0.05)
dispute gross        0.1 BOT   (buyer 0.06 + seller 0.0396 + fee 0.0004)
total protocol fees  0.0014 BOT (agreement 0: 0.001 + agreement 1: 0.0004)
accruedFees          0.0014 BOT
escrow balance       0.0014 BOT
principal loss       0 wei
```

## Tests

- Foundry: **112 tests, 0 failures** (7 suites: lifecycle, disputes, admin,
  authorization, token-edge, security/fuzz, stateful invariants).
- Coverage (`forge coverage --ir-minimum`): **98.56% lines / 98.37% statements /
  97.44% branches / 100% functions**.
- Fuzz: 4 fuzz tests; 1,024 runs default profile, 4,096 runs CI profile.
- Invariants: 3 suites (native+token solvency, state/cursor consistency,
  milestone-sum/id monotonicity); 128 x 64 default, 256 x 128 CI.
- Frontend: `pnpm lint`, `pnpm typecheck`, `pnpm build`, and the chain-safety checks
  all pass.
- CI: `.github/workflows/ci.yml` (contracts, frontend, tooling/evidence jobs).
  Remote CI status is visible on the branch/PR Actions tab.

## Indexing

Measured on 2026-10-08 (`docs/evidence/bot-rpc-capability.md`):

- `eth_getLogs` works today on both `rpc.bohr.life` (968) and `rpc.botchain.ai` (677),
  contrary to the published statement that it is disabled.
- No hard server-side range cap was observed (empty-filter scans of ~full history
  succeed). Reliability is governed by result volume: Bohr 2,048,000 blocks =
  2,214 logs / 1.38 s, 4,096,000 blocks = 7,643 logs / 10.6 s; mainnet 64,000 blocks =
  12,365 logs / 4.02 s.
- One transient nginx 503 window was observed on Bohr; no HTTP 429 or rate-limit
  headers were seen at conservative request rates.

**Classification B: bounded-block-window polling** (A technically viable, C not
required). The existing adapter already implements bounded 2,000-block windows,
dedupe by `(chainId, contractAddress, txHash, logIndex)`, a confirmed-head checkpoint
and rescan-based reorg handling; a hosted HTTP indexer remains an optional fallback.
Availability is an observed behavior, not a guarantee - production assumptions
require BOT Chain guidance.

## Security status

**UNAUDITED.** No third-party security review has been performed. No
production-readiness claim. See `SECURITY.md` and `docs/THREAT_MODEL.md`.

## Mainnet

**NOT DEPLOYED.** Chain 677 has been used strictly read-only for RPC capability
testing. Deploy scripts refuse mainnet unless `ALLOW_MAINNET_DEPLOYMENT=true`; the
frontend ignores mainnet selection unless `NEXT_PUBLIC_ALLOW_MAINNET=true`, defaults
to testnet, and blocks wrong-network writes.

## Remaining gates

- Independent security review with findings resolved.
- Production indexing with reorg monitoring and alerting (bounded scan works today).
- Public frontend deployment with mainnet disabled by default.
- Owner/fee-recipient custody decision (multisig) and documented key management.
- Incident/migration procedure for a non-upgradeable contract.
- Confirmed EVM/finality compatibility with BOT Chain guidance.
- Bug-bounty or equivalent review window.
- BOT Chain engineering sign-off.
