# NexEscrow — Final Builder Validation

> **UNAUDITED. TESTNET STAGE. NOT PRODUCTION READY.**
> No independent security audit has been performed. No production-readiness claim is
> made anywhere in this document. BOT Chain mainnet (677) has never been deployed to.
>
> **Historical execution record:** this document describes the 2026-10-14 run at
> `7d1832b`. Current BOT guidance, the 2026-10-15 retry fix and the controlled next-step
> plan are recorded in `BOT-CONTROLLED-VALIDATION-2026-10-14.md`.

---

## 1. Execution identity

| Field | Value |
|---|---|
| Execution window (UTC) | 2026-10-14T02:02:05Z → 2026-10-14T02:09:42Z |
| Branch | `feat/botchain-integration` |
| Validated tree SHA | `7d1832b5f09845703938e8eb10cc049956e8ede3` |
| Validated tree (git tree) | `70e029427ddc1d81f4cca1834f224136f376e569` |
| Origin | `https://github.com/Rishidar-lab/nexescrow` |
| PR | [#1](https://github.com/Rishidar-lab/nexescrow/pull/1) — OPEN, non-draft, MERGEABLE, not merged |
| CI (at validated tree) | run [38105145398](https://github.com/Rishidar-lab/nexescrow/actions/runs/38105145398) — **success** (Scripts / Contracts / Frontend) |
| Local toolchain | forge 1.5.1-stable · solc 0.8.26 · Node v22.23.3 · pnpm 11.21.0 · Python 3.12.3 · jq 1.7 |

All newly reported validation measurements below were **produced in this execution**;
historical figures are identified where used. The closeout changes made after the
validated tree are **documentation-only**; no contract, script, workflow, or frontend
source file was modified.

---

## 2. CONTRACTS — validation matrix

Canonical directory: `contracts/`

| Step | Command | Result |
|---|---|---|
| Format | `forge fmt --check` | **PASS** (no diff) |
| Build | `forge build --sizes` | **PASS** (exit 0) |
| Unit + fuzz + invariant (default) | `forge test -vvv` | **PASS** — 8 suites, 130/130 |
| CI/stress profile | `FOUNDRY_PROFILE=ci forge test -vvv` | **PASS** — 8 suites, 130/130 |
| Coverage | `forge coverage --ir-minimum --report summary` | **PASS** (exit 0) |
| Gas report | `forge test --gas-report` | **PASS** (exit 0) |

### 2.1 Exact test results

**Suites: 8. Tests: 130. Passed: 130. Failed: 0. Skipped: 0.**

| # | Suite | Tests |
|---|---|---|
| 1 | `NexusEscrow.Lifecycle.t.sol` | 33 |
| 2 | `NexusEscrow.Admin.t.sol` | 21 |
| 3 | `NexusEscrow.Authorization.t.sol` | 20 |
| 4 | `NexusEscrow.Disputes.t.sol` | 19 |
| 5 | `NexusEscrow.DeployGuards.t.sol` | 18 |
| 6 | `NexusEscrow.TokenEdge.t.sol` | 12 |
| 7 | `NexusEscrow.Security.t.sol` | 4 |
| 8 | `NexusEscrow.Invariants.t.sol` | 3 |
| | **Total** | **130** |

Identical totals on the default and CI profiles; only the fuzz/invariant campaign
intensity differs.

### 2.2 Fuzz configuration and result

4 property tests:

| Test | Profile | Runs | Result |
|---|---|---|---|
| `testFuzz_MilestoneSumMatchesTotal(uint8,uint128)` | default | 1024 | PASS |
| `testFuzz_DisputeSplitConservesAmount(uint128,uint16)` | default | 1024 | PASS |
| `testFuzz_FeeNeverExceedsAmount(uint128,uint16)` | default | 1024 | PASS |
| `testFuzz_Rounding_NoWeiCreatedOrDestroyed(uint128,uint16)` | default | 1024 | PASS |
| all four | `ci` | **4096** | PASS |

### 2.3 Invariant configuration and result

3 stateful invariants driven by `EscrowHandler` (create / fund / approve / raise /
resolve / cancel / withdrawFees / setProtocolFee / togglePause / warp), spanning both
native BOT and an ERC-20:

| Profile | Runs × depth | Calls per invariant | Reverts | Discards | Result |
|---|---|---|---|---|---|
| `default` | 128 × 64 | 8,192 | **0** | 0 | PASS |
| `ci` | 256 × 128 | **32,768** | **0** | 0 | PASS |

`invariant_Solvency` asserts **exact** backing:

```
address(escrow).balance      == sum(Pending/Disputed milestone amounts, native) + accruedFees[0]
token.balanceOf(escrow)      == sum(Pending/Disputed milestone amounts, ERC-20) + accruedFees[token]
```

— i.e. never under-collateralised and never over-paid, under any interleaving of
admin, pause, time-warp, dispute and resolution paths.

### 2.4 Coverage (recomputed this run)

**`src/NexusEscrow.sol`:**

| Metric | Value |
|---|---|
| Lines | **98.56 %** (137/139) |
| Statements | **98.37 %** (181/184) |
| Branches | **97.44 %** (38/39) |
| Functions | **100.00 %** (20/20) |

**Deploy path** (these exist specifically so the mainnet guard has automated proof):

| File | Lines | Statements | Branches | Funcs |
|---|---|---|---|---|
| `script/DeployPolicy.sol` | 100.00 % (13/13) | 100.00 % (14/14) | 100.00 % (4/4) | 100.00 % (4/4) |
| `script/DeployNexusEscrowBOT.s.sol` | 100.00 % (19/19) | 100.00 % (22/22) | 0.00 % (0/2) | 100.00 % (1/1) |
| `script/DeployNexusEscrow.s.sol` | 92.31 % (24/26) | 93.33 % (28/30) | 50.00 % (2/4) | 100.00 % (1/1) |

**Whole-project total** (includes OpenZeppelin + test + mock sources):

| Metric | Value |
|---|---|
| Lines | 76.77 % (476/620) |
| Statements | 79.79 % (466/584) |
| Branches | 64.29 % (81/126) |
| Functions | 77.40 % (113/146) |

Raw output: `docs/evidence/coverage-summary.txt`.

---

## 3. FRONTEND — validation matrix

Canonical directory: `frontend/`

| Step | Command | Result |
|---|---|---|
| Locked install | `pnpm install --frozen-lockfile` | **PASS** (exit 0, lockfile honoured) |
| Lint | `pnpm lint` | **PASS** (exit 0, no findings) |
| Typecheck | `pnpm typecheck` | **PASS** (`next typegen` + `tsc --noEmit`) |
| Unit tests | `pnpm test` | **PASS** — 35/35 |
| Chain safety | `pnpm check:chain-safety` ×4 | **PASS** ×4 (see §3.2) |
| Finality policy | `pnpm check:finality-policy` | **PASS** ("finality policy regression checks passed") |
| Production build | `pnpm build` | **PASS** — 6 routes, env from `.env.production` |

### 3.1 Unit tests

**35 tests, 35 passed, 0 failed** — `chain.test.ts` 13, `finality.test.ts` 12,
`indexer.test.ts` 10.

### 3.2 Chain-safety matrix (observed resolver output)

| Scenario | `NEXT_PUBLIC_CHAIN_ID` | `ALLOW_MAINNET` | `selectedChainId` | Chains offered | Expected | Result |
|---|---|---|---|---|---|---|
| CI: default build is testnet | (unset) | false | **968** | 3945, 968 | 968 | PASS |
| CI: mainnet without opt-in fails closed | 3946 | false | **968** | 3945, 968 | 968 | PASS |
| CI: unknown chain fails closed | 1 | false | **968** | 3945, 968 | 968 | PASS |
| CI: explicit opt-in honours request | 3946 | true | 3946 | 3945, 3946, 968, 677 | 3946 | PASS |
| **BOT 677 without opt-in fails closed** | **677** | false | **968** | 3945, 968 | 968 | **PASS** |
| **BOT 677 with opt-in honoured** | **677** | true | 677 | 3945, 3946, 968, 677 | 677 | **PASS** |
| **BOT 677 as default-chain, no opt-in** | (unset) | false | **968** | 3945, 968 | 968 | **PASS** |
| No env vars at all | (unset) | false | **968** | 3945, 968 | 968 | PASS |

Rows in bold were executed in this closeout specifically to prove the BOT 677 guard
(the committed CI matrix exercises 3946 for the mainnet fail-closed case).

---

## 4. SCRIPTS — validation matrix

| Step | Command | Result |
|---|---|---|
| Workflow/YAML | `yaml.safe_load` over `.github/workflows/*.yml` | **PASS** ("workflow yaml OK") |
| Python syntax | `python3 -m py_compile scripts/*.py` | **PASS** (4 files) |
| Shell syntax | `bash -n scripts/deploy-bot-968.sh` | **PASS** |
| Validator unit tests | `python3 -m unittest discover -s tests` | **PASS** — 6/6 (dispute fee arithmetic) |
| Evidence JSON well-formed | `jq -e .` ×3 | **PASS** |
| Evidence verifier (local) | `verify-bot-968-evidence.py` | **PASS** — 26/26 |
| Evidence verifier (on-chain) | `verify-bot-968-evidence.py --rpc-url https://rpc.bohr.life` | **PASS** — **34/34** |

---

## 5. Existing Bohr 968 evidence — re-verification

The 2026-10-08 validated deployment was re-queried from chain in this execution.
**Read-only only: no transaction was sent.**

| Field | Value |
|---|---|
| Chain | BOT Chain Bohr **testnet**, chain id **968** (`cast chain-id` → 968) |
| Contract | `0x6448668ae9cbbc41617c2bd5e4f29279320a2700` |
| Deployment tx | `0x4216d1e1eb33e296e3a3040baa723b507ce2da449d60e6ffe9456cecacf6da61` |
| Deployment block | `26178651` |
| Deployment receipt | `status=1 (success)`, `contractAddress` matches, `gasUsed=1513781` |
| Runtime bytecode keccak256 | `0x7fba19dd52ec2caff42086cc4af9f342caed5564fc1240557e779e1353ea59a7` — **matches manifest** |
| Runtime bytecode size | 6,309 bytes |
| RPC head at re-verification | 26,778,669 |

### 5.1 Lifecycle receipts (all re-confirmed on chain)

| Step | Tx | Block | Status |
|---|---|---|---|
| createAgreement(A) | `0xf9f4b64c…d78608` | 26178658 | 1 |
| fund(A) | `0xe52792a7…760a1d` | 26178662 | 1 |
| approveMilestone(A,0) | `0x42bcb860…ef746e` | 26178664 | 1 |
| approveMilestone(A,1) | `0xba6e7855…c39b1` | 26178666 | 1 |
| createAgreement(B) | `0x1b49e4e2…36d560` | 26178669 | 1 |
| fund(B) | `0xb8115ec9…2774fb` | 26178671 | 1 |
| raiseDispute(B, seller) | `0x37275e2a…009bd` | 26178673 | 1 |
| resolveDispute(B, 6000) | `0x3a53ede3…a2221` | 26178675 | 1 |

### 5.2 Emitted events (live re-query, 11 logs, identity set matches committed evidence)

| Event | Count |
|---|---|
| `OwnershipTransferred` | 1 |
| `AgreementCreated` | 2 (ids 0, 1) |
| `Funded` | 2 |
| `MilestoneReleased` | 2 |
| `DisputeRaised` | 1 |
| `DisputeResolved` | 1 |
| `AgreementCompleted` | 2 |
| **Total** | **11** |

No unknown event topics (`unknown=0`).

### 5.3 Final on-chain agreement states

| Read | Agreement A (id 0) | Agreement B (id 1) |
|---|---|---|
| buyer / seller / arbiter | `0xBd44…64af` / `0x0066…bF8E` / `0x617B…C433` | same |
| token | `0x0000…0000` (native BOT) | native BOT |
| totalAmount | 100000000000000000 | 100000000000000000 |
| feeBps | 100 | 100 |
| status | **2 = Completed** | **2 = Completed** |
| nextMilestone / milestoneCount | 2 / 2 | 1 / 1 |
| milestones | `[(5e16, Released), (5e16, Released)]` | `[(1e17, Resolved)]` |

`nextAgreementId == 2` on chain (exactly two agreements ever created).

### 5.4 Asset conservation — exact arithmetic

Fee rate 100 bps; `BPS_DENOMINATOR = 10000`.

**Agreement A — normal milestone flow** (total 0.1 BOT = 100000000000000000):

```
m0: amount 50000000000000000  fee = 50000000000000000*100/10000 =       500000000000000
m1: amount 50000000000000000  fee = 50000000000000000*100/10000 =       500000000000000
released gross                    = 100000000000000000
fees A                             =          1000000000000000
paid to seller                     =  99000000000000000   (2 x 49500000000000000)
```

**Agreement B — dispute/arbitration flow** (total 0.1 BOT = 100000000000000000, `buyerBps = 6000`):

```
amount                             = 100000000000000000
buyerAmount = 100000000000000000*6000/10000 =  60000000000000000
sellerGross = 100000000000000000 - 60000000000000000 = 40000000000000000
fee         = 40000000000000000*100/10000  =          400000000000000
sellerAmount = 40000000000000000 - 400000000000000  = 39600000000000000
dispute gross = 100000000000000000
```

**Aggregate:**

```
funded in                 100000000000000000 + 100000000000000000 = 200000000000000000
paid to seller             99000000000000000 +  39600000000000000 = 138600000000000000
refunded to buyer                                                =  60000000000000000
accrued as fees             1000000000000000  +         400000000000000 =   1400000000000000
                                        ----------------------------------------------
out total                138600000000000000 +  60000000000000000 + 1400000000000000
                                                                       = 200000000000000000

DELTA = 0   -> conservation EXACT
```

On-chain corroboration:

```
escrow balance            = 1400000000000000
accruedFees(address(0))   = 1400000000000000   -> escrow holds fees and nothing else
principal still in escrow = 0 wei
```

Rounding is exact by construction: floor division leaves the remainder with the
seller, so no wei is created or destroyed. `testFuzz_Rounding_NoWeiCreatedOrDestroyed`
(1024/4096 runs) and `testFuzz_DisputeSplitConservesAmount` cover this generically.

### 5.5 Evidence integrity

Historical evidence was **not modified**. Only the three *reproducible* forge output
captures were regenerated from this run so they match the current tree:

- `docs/evidence/contracts-test-run.txt` (was 112 tests / 7 suites)
- `docs/evidence/coverage-summary.txt` (was 112 tests / 7 suites, Total 70.65 %)
- `docs/evidence/gas-report.txt` (was 112 tests / 7 suites)

**Untouched (irreducible chain facts):** everything under `docs/evidence/bot-968/`,
`bot-rpc-capability.json` / `.md`, `mainnet-guard-677.log`, `chain-resolution.txt`,
`local-968-*.log`, `slither*`. In particular `deployment.json.gitCommit =
0293094a81d32dfa92d437e63edbadb0304e50ba` remains the historical commit-at-deployment
and was **not** rewritten.

**Result: PASS — 34/34 on-chain checks, 0 failures.**

---

## 6. Fresh Bohr 968 run

**BLOCKED.** No operator testnet signing keys are available in this execution
environment (`PRIVATE_KEY`, `SELLER_KEY`, `ARBITER_KEY` unset; no `contracts/.env`;
no Foundry keystore). Both harnesses read keys only from the environment and have no
on-disk fallback.

**No new transactions were sent. No new evidence was created. Nothing was fabricated.**

Recorded in `docs/evidence/FRESH_TESTNET_RUN_BLOCKED.md`.

---

## 7. BOT 677 guard — proof

| Claim | Evidence |
|---|---|
| Default build is testnet-safe | `resolveSelectedChainId()` falls back to `CHAIN_IDS.botTestnet` (968); `supportedChains` filters to `testnet === true` unless opted in. Observed: `offered = [3945, 968]` — **677 is never offered** |
| 677 is not auto-selected | Observed resolver output with `NEXT_PUBLIC_CHAIN_ID=677` and no opt-in → `selectedChainId: 968`, `allowMainnet: false`, warning: *"Mainnet chain 677 requested, but NEXT_PUBLIC_ALLOW_MAINNET is not \"true\". This build failed closed to BOT Bohr testnet (968)."* |
| Same via the default-chain variable | `NEXT_PUBLIC_DEFAULT_CHAIN_ID=677` without opt-in → **968** |
| Unknown chain fails closed | `NEXT_PUBLIC_CHAIN_ID=1` → **968**, warning *"Unknown chain id 1; failed closed…"* |
| Deployment to 968 requires explicit intent | `deploy-bot-968.sh` aborts unless `CONFIRM_BOT_968_DEPLOY=BOT-968`, and re-verifies `chain id == 968` **before** any other action |
| 968 deploy script refuses mainnet unconditionally | `DeployNexusEscrowBOT` calls `DeployPolicy.requireBotTestnetOnly(block.chainid)`, which **ignores** `ALLOW_MAINNET_DEPLOYMENT` entirely; covered by `test_Wiring_BOTScript_RefusesMainnet677` and `testBOT_Policy_RejectsEveryChainExcept968` (677 in 100 % line / 100 % function coverage) |
| Generic script blocks mainnet by default | `requireMainnetOptIn` reverts with `MAINNET DEPLOYMENT BLOCKED: set ALLOW_MAINNET_DEPLOYMENT=true only after independent security review`; `test_Mainnet_Blocked_RegardlessOf_AnyOtherInput` |
| Wallet chain mismatch blocks writes | `useEscrowWrite.write()` fails with phase `wrong-network` unless `isCorrectChain(walletChainId)`; the call is additionally submitted with an explicit `chainId: selectedChainId` so wagmi/viem refuses rather than falls back |
| Unconfigured chain disables writes | `escrowConfigured === false` → phase `unconfigured`; `createIndexer()` returns `null` rather than querying the zero address |
| Committed production defaults | `frontend/.env.production`: `NEXT_PUBLIC_CHAIN_ID=968`, `NEXT_PUBLIC_ALLOW_MAINNET=false`, 968 contract `0x6448…2700` |

```
BOT MAINNET 677:  NOT DEPLOYED
                 NOT ENABLED
                 NOT PRODUCTION READY
```

No BOT 677 transaction was executed at any point in this validation. Chain 677 was
contacted **read-only** for the pre-existing RPC capability measurements.

---

## 8. RPC observations (empirical only — **not** BOT Chain policy)

These are *measurements*, recorded from `docs/evidence/bot-rpc-capability.json`
(probed 2026-10-08). They are **not** a specification and must not be cited as one.

- `eth_getLogs` was reachable on both official endpoints; **no hard range cap observed**
  (an empty-filter probe over 32,000,000 blocks returned `200 OK` with `[]`).
- Reliability and latency scale with **result volume**, not with range width:
  64,000 blocks → 12,365 logs / ~4.0 s median; 2,048,000 blocks → 2,214 logs / 1.38 s;
  4,096,000 blocks → 7,643 logs / 10.6 s.
- A transient nginx **503** window was observed; retries with backoff recovered. No
  429 and no rate-limit headers were ever seen.
- **None of this is a guarantee.** Supported ranges, official limits, rate limits and
  recommended retry behaviour remain **WAITING ON BOT CHAIN ENGINEERING**.

---

## 9. Empirical Cancun observation (empirical only — **not** BOT Chain policy)

- `contracts/foundry.toml` pins `evm_version = "cancun"` (solc 0.8.26 defaults to
  Cancun; the pin is explicit rather than implicit).
- The validated 968 deployment manifest records `evmVersion: "cancun"`, and
  `scan.bohr.life` reports the source as verified (`is_verified: true`, solc 0.8.26,
  cancun). The runtime bytecode hash on chain matches the manifest exactly.
- Deployment and full lifecycle on Bohr 968 executed successfully under that target.

This was originally an empirical observation only. On 2026-10-14 Cisco's guidance,
relayed by Leon, confirmed **Cancun** as the EVM target for 968/677. The observation
therefore matches the later guidance. Opcode/precompile limitations remain open, and
the Hardhat example's Solidity 0.8.28 was not stated as a compiler minimum.

---

## 10. BOT guidance status (updated 2026-10-15)

| # | Item | Status |
|---|---|---|
| 1 | `eth_getLogs` | **PARTIAL** — 2,000 blocks/query confirmed; no configured rate limit reported; retry/backoff recommendation still open |
| 2 | Confirmations/finality | **PARTIAL** — 2 receipt confirmations confirmed for 968/677; reorg guarantee and indexing depth still open |
| 3 | Cancun / EVM | **PARTIAL** — Cancun target confirmed; opcode/precompile limitations still open |

`FINALITY_POLICY_BY_CHAIN` records the BOT-confirmed receipt count
(`writeReceiptConfirmations: 2`) separately from NexEscrow's application-owned
`indexingSafetyDepth: 12`. The latter is explicitly not BOT production-finality
guidance.

**Empirical measurements and BOT Chain policy are kept strictly separate throughout
this repository.**

---

## 11. Defects found and fixed in this closeout

At this historical closeout, **none** was reported. A later 2026-10-15 review
reproduced one scoped frontend defect: the text-based retry classifier could retry a
permanent typed `RpcRequestError` whose message contained `429/502/503/504`. Commit
`a149a0d8100e8dd88b087ff5d80aaa530db5e46a` replaces that with typed viem error/status
classification and regression coverage. The retry path is read-only `eth_getLogs`;
transaction submission was never retried.

The audit covered, with no defect found: escrow authorization; release / refund /
dispute / arbitration transitions; exact asset conservation; native-token accounting;
ERC-20 assumptions; fee-on-transfer rejection; rounding and dust; failed-payout
behaviour (atomic revert, no partial state); owner / admin / arbitrator authority
separation; reentrancy exposure; chain-mismatch protection; unknown-chain fail-closed
behaviour; the BOT 677 mainnet guard; indexer safe-head handling; checkpointing;
deduplication; reorg rescan behaviour; malformed RPC/indexer responses; retry/backoff;
stale frontend state; and frontend chain selection/finality logic.

No defect was invented to satisfy the count. The only corrections made were to
**factually stale documentation** (see §12), plus regeneration of three reproducible
forge output captures.

---

## 12. Documentation reconciliation

All stale numbers were corrected; nothing else was touched.

| File | Was | Now |
|---|---|---|
| `README.md` | 112 tests | 130 tests, 8 suites |
| `README.md` | `forge test  # 112 tests` | `# 130 tests` |
| `docs/BOTCHAIN_INTEGRATION.md` | 112 Foundry tests (x2) | 130 Foundry tests, 8 suites |
| `docs/BOTCHAIN_VALIDATION_SUMMARY.md` | 112 tests, 7 suites | 130 tests, 8 suites |
| `docs/DEPLOYMENT_RUNBOOK.md` | `forge test  # 112 tests` | `# 130 tests` |
| `docs/ECOSYSTEM_PROPOSAL.md` | 112 passing tests | 130 passing tests, 8 suites |
| `docs/TESTNET_EVIDENCE.md` | 112 tests / 7 suites + breakdown | 130 tests / 8 suites + breakdown incl. deploy guards |
| `docs/evidence/contracts-test-run.txt` | 112 / 7 suites (2026-10-08) | regenerated 130 / 8 suites (2026-10-14) |
| `docs/evidence/coverage-summary.txt` | 112 / 7 suites, Total 70.65 % | regenerated 130 / 8 suites, Total 76.77 % |
| `docs/evidence/gas-report.txt` | 112 / 7 suites | regenerated 130 / 8 suites |

Left deliberately unchanged because still accurate: all contract coverage figures for
`src/NexusEscrow.sol` (98.56 / 98.37 / 97.44 / 100 reproduced exactly), the PR's Bohr
evidence hashes, the mainnet gate checklists, the "NOT DEPLOYED" 677 status, and the
`112` occurrences inside `bot-rpc-capability.*` and `gas-report.txt`, which are RPC
result counts and a gas figure — not test counts.

---

## 13. Secret hygiene

| Check | Result |
|---|---|
| `.env` tracked in git | none (only `.env.example` templates and `frontend/.env.production`, which is public build config) |
| `PRIVATE_KEY = 0x…` assignments in tracked files | none |
| Mnemonic / seed / passphrase literals | none outside vendored `forge-std` public Anvil test fixtures |
| Tracked files matching secret/key/credential names | none |

`contracts/lib/forge-std` is vendored in-tree and contains only the publicly known
Anvil dev keys in upstream test fixtures. Nothing in `docs/`, `scripts/`, or `tests/`
contains key material. Evidence files were checked for key-shaped literals: none.

---

## 14. Final status

```
CONTRACTS:          PASS   8 suites / 130 tests / 130 pass / 0 fail
FUZZ:               PASS   4 properties x 1024 (default) / 4096 (ci)
INVARIANTS:         PASS   3 invariants, 8,192 calls (default) / 32,768 (ci), 0 reverts
COVERAGE:           PASS   contract 98.56 L / 98.37 S / 97.44 B / 100.00 F
FRONTEND:           PASS   lint, typecheck, 35/35 unit, 8/8 chain-safety, finality, build
SCRIPTS:            PASS   yaml, py, sh, 6/6 unittest, jq, 34/34 evidence verifier
EVIDENCE:           PASS   968 re-verified live, 34/34, conservation exact
FRESH 968 RUN:      BLOCKED (no operator testnet keys; nothing fabricated)
MAINNET GUARDS:     PASS   677 not deployed / not enabled / not reachable by default

BUILDER-CONTROLLED STATUS: COMPLETE

BOT-CHAIN-CONTROLLED:
  eth_getLogs policy ............ WAITING
  confirmation/finality policy . WAITING
  Cancun/EVM policy ............ WAITING

BOT 677: DISABLED
```

---

> **Disclaimer.** NexEscrow is **UNAUDITED**. It has never been deployed to BOT Chain
> mainnet (677) or any other mainnet. No audit has been completed, none is claimed, and
> no production readiness is asserted. BOT Chain policy on `eth_getLogs`, finality and
> Cancun/EVM compatibility is unresolved and remains outstanding with BOT Chain
> engineering.
