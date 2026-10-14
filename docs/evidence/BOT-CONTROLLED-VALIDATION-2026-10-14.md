# BOT Chain — Smallest Controlled Validation (Bohr 968)

- **Recorded (UTC):** 2026-10-14T14:07:51Z
- **Operator request answered:** "the smallest controlled validation step you would
  recommend next, including the remaining checks and stop conditions."
- **Outcome:** **PASS for every arm that does not require operator signing keys.**
  The on-chain *write* arm (a fresh lifecycle run) was **not performed** — its
  precondition (funded burner testnet keys) is not met in this environment. Nothing
  about that arm was fabricated.

---

## 1. Purpose

Define and execute the **smallest** evidence-producing validation that materially
increases confidence in the NexEscrow × BOT Chain integration **without** depending on
BOT/Cisco's three unanswered network-policy questions (eth_getLogs limits/retry,
finality/reorg depth, Cancun opcode/precompile limits), and **without** touching BOT
mainnet 677.

This document is a self-contained re-execution recorded in this session. It does not
replace the deeper package in `docs/BOTCHAIN_VALIDATION_SUMMARY.md`,
`docs/evidence/FINAL-BUILDER-VALIDATION.md` or `docs/TESTNET_EVIDENCE.md`; it is the
minimal, reproducible core, re-run and re-confirmed today.

## 2. Scope

**In scope (executed this session):**
- Builder-controlled checks: `forge fmt --check`, `forge build`, full `forge test`,
  frontend unit tests, frontend chain-safety + finality-policy checks, Python
  validator unit tests.
- Read-only on-chain re-verification of the **existing** validated Bohr 968 deployment
  (no new transactions, no funds moved).
- Static review of the mainnet guard, the finality policy, the bounded log-scan
  indexer, and the RPC retry policy against the stop conditions below.

**Explicitly out of scope:**
- Any transaction on BOT mainnet 677 (forbidden).
- Any new on-chain write on Bohr 968 (blocked — no signer; see §13).
- Any claim that depends on BOT/Cisco's pending answers (§14).
- Any security-audit, production-readiness, or funding judgement (§15).

## 3. Exact commit SHA

- Branch: `feat/botchain-integration`
- HEAD: `5d4176a0529e25032f0e0bb63a26df00a29fe9e6`
- Worktree: clean; local HEAD == `origin/feat/botchain-integration` (no unpushed
  commits at the time of the run).

## 4. Network used

- BOT Chain **Bohr testnet**, chain id **968** (`0x3c8`).
- RPC: `https://rpc.bohr.life` — read-only (`eth_chainId`, `eth_blockNumber`,
  `eth_getCode`, `eth_getLogs`, receipt/call reads only).
- Observed head block at run time: `0x1997c12` = **26,835,986**.
- BOT mainnet 677: **not contacted for any write; disabled** (see §F / §10).

## 5. Contract / deployment identifiers (existing instance re-verified)

| Item | Value |
|---|---|
| Address | `0x6448668ae9cbbc41617c2bd5e4f29279320a2700` |
| Deployment tx | `0x4216d1e1eb33e296e3a3040baa723b507ce2da449d60e6ffe9456cecacf6da61` |
| Deployment block | `26178651` (receipt `status=1`, re-confirmed) |
| Runtime bytecode | present on chain (len 12,620 hex chars); hash matches the committed manifest |
| Owner | throwaway key generated for the original run and discarded; admin functions inert — this instance is a validation artifact, not a service |

Provenance (STOP-03): the on-chain runtime bytecode hash equals the manifest hash in
`docs/evidence/bot-968/`, which ties to the explorer-verified source
(solc `v0.8.26+commit.8a97fa7a`, optimizer on, `evm_version: cancun`).

## 6. Preconditions

- Toolchain present: forge/cast 1.5.1-stable, node v22.23.3, pnpm 10.34.6,
  python 3.12.3, slither 0.11.5, jq, curl.
- `foundry.toml`: `solc_version = "0.8.26"`, `evm_version = "cancun"`, optimizer on
  (200 runs).
- Signer keys for a *fresh* run: **absent** (`PRIVATE_KEY`, `SELLER_KEY`,
  `ARBITER_KEY` unset; no `contracts/.env*`; no Foundry keystore). Presence was
  checked; **no key value was ever read, printed, or searched for.**

## 7. Procedure

1. Establish ground truth: git state, toolchain, signer-env presence, RPC reach.
2. Run the builder-controlled checks (contracts, frontend, Python).
3. Read-only RPC probe (chainId / head / contract code).
4. Re-run the reproducible on-chain verifier against live chain.
5. Statically review guard / finality / indexer / retry source against §12 stop
   conditions.
6. Adversarial review (§ below) to try to falsify the PASS.
7. Record evidence; make no code change absent a demonstrated defect.

## 8. Checks executed & 9. Results

### Builder-controlled (local, deterministic)

| Check | Command | Result |
|---|---|---|
| Format | `forge fmt --check` | exit 0 — clean |
| Build | `forge build` | exit 0 — compiles under solc 0.8.26 + cancun |
| Contract tests | `forge test` | **130 passed / 0 failed / 0 skipped — 8 suites** |
| Frontend unit tests | `pnpm -s test` | **35 passed / 0 failed** |
| Chain-safety | `pnpm -s check:chain-safety` | `{selectedChainId:968, allowMainnet:false, offered:[3945,968], warning:null}` — **677 absent from offered set** |
| Finality-policy | `pnpm -s check:finality-policy` | "finality policy regression checks passed" |
| Validator unit tests | `pytest tests/` | **6 passed** |

8 contract suites (exact counts from this run): Authorization 20, Disputes 19,
DeployGuards 18, Admin 21, Lifecycle 33, TokenEdge 12, Security/fuzz 4,
Invariants 3 — total **130**.

### On-chain read-only (live Bohr 968)

| Check | Result |
|---|---|
| `eth_chainId` | `0x3c8` = **968** |
| `eth_blockNumber` | `0x1997c12` = 26,835,986 |
| `eth_getCode` @ deployment | bytecode present (12,620 hex) |
| `verify-bot-968-evidence.py --rpc-url https://rpc.bohr.life` | **34 PASS / 0 FAIL** |

Key verifier assertions re-confirmed against chain today: rpc chainId == 968;
deployed bytecode hash == manifest; deployment receipt success @ block 26178651; all
**8 lifecycle receipts `status=1`**; conservation `released gross + dispute gross ==
funded total`, `escrow balance == accruedFees`, **principal loss 0 wei**; re-queried
event identity set `recorded=11 live=11`; `nextAgreementId == 2`;
`accruedFees == 0.0014 BOT` on-chain.

### Static review against the stop conditions

- **Mainnet guard** (`contracts/script/DeployPolicy.sol`): `requireBotTestnetOnly`
  reverts for any chain id ≠ 968 (incl. 677); `requireMainnetOptIn` refuses
  677/3946 unless `ALLOW_MAINNET_DEPLOYMENT=true` (never default). Proven by
  `NexusEscrow.DeployGuards.t.sol` (part of the 130).
- **Finality policy** (`frontend/src/lib/finality.ts`): `writeReceiptConfirmations=2`
  and `indexingSafetyDepth=12` are distinct fields with an explicit comment that
  neither is claimed to be BOT's production finality.
- **Log scan** (`frontend/src/lib/indexer/logScan.ts`): bounded 2,000-block windows
  (`chunkSize = 2_000n`), dedupe by `(chainId, contractAddress, txHash, logIndex)`,
  rescan-replace reorg handling, excludes the newest 12 blocks, refuses a
  cross-chain client; never falls back to `latest`.
- **HTTP indexer** (`frontend/src/lib/indexer/http.ts`): single timed fetch, validates
  and drops cross-chain/malformed rows — no retry amplification.
- **Retry policy** (`scripts/probe-bot-rpc*.py`): retries only transient HTTP
  {429,502,503,504} + timeout/network; semantic responses break out of the loop
  (never blindly retried); bounded by `MAX_ATTEMPTS`.

## 10. Transaction hashes / block numbers

**No new transactions were produced by this validation.** All on-chain references in
§5 and §9 are *historical* receipts from the 2026-10-08 run, re-confirmed read-only.
No hash in this document is new. See `docs/BOTCHAIN_VALIDATION_SUMMARY.md` for the
full lifecycle/dispute hash tables.

## 11. CI / test command results

Local re-execution results are in §8–§9 (all green). Remote CI
(`.github/workflows/ci.yml`: Scripts, Contracts, Frontend jobs) is visible on the PR
#1 Actions tab; the last operator-recorded green run is noted in the email draft
(`EMAIL_DRAFT_LEON_CISCO.md`). **Green CI proves only that the recorded commands
passed on the runner — it is not finality, audit, or production evidence.**

## 12. Stop conditions (definitions)

| ID | Condition |
|---|---|
| STOP-01 | RPC reports a chainId other than 968 |
| STOP-02 | A script attempts to select/deploy/transact on 677 |
| STOP-03 | Deployed bytecode ≠ intended Bohr deployment / provenance unestablished |
| STOP-04 | A transaction unexpectedly involves non-test/customer funds |
| STOP-05 | A lifecycle tx reverts unexpectedly, cause not conclusively attributable |
| STOP-06 | State transitions violate the escrow state machine |
| STOP-07 | Balance conservation fails for a milestone/dispute/refund flow |
| STOP-08 | Event data materially disagrees with contract state |
| STOP-09 | Indexer produces missing/duplicated/reordered/inconsistent state after reconciliation |
| STOP-10 | A required log query exceeds the 2,000-block application cap |
| STOP-11 | Retry becomes unbounded or retries semantic/RPC errors incorrectly |
| STOP-12 | Compiler/EVM incompatibility under solc 0.8.26 + Cancun |
| STOP-13 | Validation requires assuming an undocumented finality/reorg guarantee |
| STOP-14 | Validation requires assuming an opcode/precompile guarantee Cisco has not given |
| STOP-15 | Any step would require describing the system as audited/production-ready/approved |

## 13. Whether any stop condition triggered

**None triggered.**

| STOP | Status | Evidence |
|---|---|---|
| 01 | clear | chainId `0x3c8` = 968 |
| 02 | clear | guard reverts for 677; frontend offered set `[3945,968]`, `allowMainnet:false` |
| 03 | clear | runtime bytecode hash == manifest; explorer-verified source |
| 04 | clear | no transaction sent; no funds moved |
| 05 | clear | no lifecycle tx attempted this session; historical receipts all `status=1` |
| 06 | clear | both agreements terminal `Completed`; invariant suites pass |
| 07 | clear | conservation exact; principal loss 0 wei |
| 08 | clear | event-derived state == direct reads; 11==11 identity match |
| 09 | clear | dedupe + rescan-replace; validator reconciliation passes |
| 10 | clear | `chunkSize = 2_000n`; no unbounded range in code path |
| 11 | clear | transient-only, bounded `MAX_ATTEMPTS`, semantic errors not retried |
| 12 | clear | builds + 130 tests pass under 0.8.26 + cancun |
| 13 | clear | 2-conf and 12-depth labelled app-side; no finality guarantee assumed |
| 14 | clear | no opcode/precompile guarantee assumed |
| 15 | clear | language scan found no affirmative "audited/approved/production-ready" |

**Separate from the stop conditions:** the fresh on-chain *write* arm was **not
performed** because its precondition (three funded burner testnet keys) is not met
here. That is a recorded precondition-not-met, not a stop-condition trip, and nothing
was fabricated to stand in for it. See `docs/evidence/FRESH_TESTNET_RUN_BLOCKED.md`.
To unblock, supply three funded **testnet** keys + `CONFIRM_BOT_968_DEPLOY=BOT-968`
and run `scripts/validate-bot-968.py` (which refuses any chain ≠ 968).

## 14. Remaining BOT-side questions (UNKNOWN — unchanged)

1. **eth_getLogs policy:** officially supported range, hard caps, rate limits, and
   recommended retry/backoff beyond our bounded transient-only policy. *(We observed
   no hard range cap and one transient 503 on our own traffic — an observation, not a
   spec.)*
2. **Finality / reorg:** recommended receipt confirmations and reorg/indexing safety
   depth for 968 and 677. *(Our 2-conf and 12-block values are app-side placeholders.)*
3. **Cancun / EVM:** official Cancun support, recommended compiler `evmVersion`, and
   any opcode/precompile limitations. *(0.8.26 + cancun builds and tests pass; 0.8.28
   was a BOT example, not established as a required minimum.)*

## 15. Explicit limitations (mandatory)

- Validation is **Bohr 968 testnet only**.
- **BOT 677 remains disabled** — not deployed, not enabled, not selectable for normal
  execution.
- **2 receipt confirmations are NOT a reorg/finality guarantee.**
- **12-block indexing depth is a NexEscrow application-side safety choice**, not
  claimed as BOT policy unless BOT states otherwise.
- This validation is **not a security audit** (the contract is **UNAUDITED**).
- This validation is **not production-readiness approval**.
- This validation is **not ecosystem-support / funding approval**.
- **Real customer funds must not be introduced** on the basis of this validation.

---

### Reproduce

```bash
# contracts
cd contracts && forge fmt --check && forge build && forge test
# frontend
cd ../frontend && pnpm test && pnpm check:chain-safety && pnpm check:finality-policy
# python validators
cd .. && python3 -m pytest tests/
# on-chain read-only re-verification (no keys, no writes)
python3 scripts/verify-bot-968-evidence.py --rpc-url https://rpc.bohr.life
```

*No fabricated tests, transaction hashes, RPC behaviour, CI results, or BOT Chain
policy appear in this document. Anything not verified in this session is labelled
UNKNOWN.*
