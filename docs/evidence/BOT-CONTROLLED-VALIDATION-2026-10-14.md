# BOT Chain — Smallest Controlled Validation (Bohr 968)

- **Recorded (UTC):** 2026-10-14T14:07:51Z
- **Operator request answered:** "the smallest controlled validation step you would
  recommend next, including the remaining checks and stop conditions."
- **Outcome:** **PASS for every arm that does not require operator signing keys.**
  The on-chain *write* arm (a fresh lifecycle run) was **not performed** — its
  precondition (funded burner testnet keys) is not met in this environment. Nothing
  about that arm was fabricated.
- **Reconciled (UTC):** 2026-10-14T14:30Z — after this doc's first draft, the branch
  received upstream commits recording BOT engineering guidance
  (`docs/evidence/BOT-ENGINEERING-GUIDANCE-2026-10-14.md`). Those were merged and the
  whole validation was **re-run against the merged state**; §3, §9, §14 and §15 below
  reflect the confirmed guidance. The confirmed items (eth_getLogs 2,000-block range,
  no rate limit; 2-block receipt confirmations for 968/677; Cancun EVM target) are no
  longer listed as unknown.
- **Reviewed (UTC):** 2026-10-15T14:10Z — Leon's 15 October request was checked
  against the current PR, email thread and implementation. A permanent-RPC-error
  retry defect was reproduced and fixed in `a149a0d8100e8dd88b087ff5d80aaa530db5e46a`;
  the original STOP-11 assessment is superseded by §13. The controlled plan in
  §§16–20 is the reviewable next-step decision record. No chain-677 action occurred.

---

## 1. Purpose

Define and execute the **smallest** evidence-producing validation that materially
increases confidence in the NexEscrow × BOT Chain integration **without** depending on
the network-policy items that remain open (retry/backoff, reorg/finality depth, Cancun
opcode/precompile limits — see §14), and **without** touching BOT mainnet 677. The
items BOT has since confirmed (§14, "Confirmed") are reflected directly in the code and
this document.

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
- **VALIDATION TARGET SHA** (the exact tree that was tested after the merge):
  **`abb432a`** — the merge commit joining the local evidence line (`9eba87c`, parent
  `5d4176a`) with the 7 upstream BOT-guidance commits (`e12939f` … `1cf547c`).
- **EVIDENCE DOCUMENT COMMIT:** a *later* `docs: reconcile controlled validation with
  BOT guidance` commit records these corrections on top of `abb432a`. That commit is
  documentation only; it does **not** test itself — the results below were produced
  against `abb432a`.
- Worktree at validation time: clean, no unrelated user changes. The initial draft
  (pre-merge) was validated against base `5d4176a`; this reconciliation re-ran the full
  suite against the merged `abb432a`, same green result.

## 4. Network used

- BOT Chain **Bohr testnet**, chain id **968** (`0x3c8`).
- RPC: `https://rpc.bohr.life` — read-only (`eth_chainId`, `eth_blockNumber`,
  `eth_getCode`, `eth_getLogs`, receipt/call reads only).
- Observed head block at run time: `0x1997c12` = **26,835,986**.
- BOT mainnet 677: **not contacted for any write; disabled** (see §10).

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
| Frontend unit tests | `pnpm -s test` | **43 passed / 0 failed** (35 pre-policy + 8 `rpcPolicy.test.ts`) |
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
- **Finality policy** (`frontend/src/lib/finality.ts`): BOT 968/677 set
  `writeReceiptConfirmations=2` (this *is* BOT's confirmed receipt-confirmation count,
  §14) and `indexingSafetyDepth=12` (a NexEscrow-owned conservative policy, *not* a BOT
  finality/reorg guarantee). The two are distinct fields; 2 confirmations is explicitly
  **not** treated as finality.
- **RPC policy** (`frontend/src/lib/rpcPolicy.ts`): `BOT_RECOMMENDED_LOG_QUERY_BLOCKS =
  2_000n` enforces BOT's recommended eth_getLogs ceiling on 968/677;
  `RPC_MAX_ATTEMPTS = 3` with exponential backoff; after the 2026-10-15 fix,
  `isRetryableRpcError` recognises typed viem HTTP 429/502/503/504 and timeout
  failures, walks wrapped causes, and fails permanent typed `RpcRequestError` objects
  closed even when their text contains a retry-looking status. The narrow plain-error
  fallback covers transport/fetch failures only.
- **Log scan** (`frontend/src/lib/indexer/logScan.ts`): bounded windows via
  `logQueryChunkSizeFor(chainId, …)` (capped at 2,000 on BOT chains), dedupe by
  `(chainId, contractAddress, txHash, logIndex)`, rescan-replace reorg handling,
  excludes the newest 12 blocks, refuses a cross-chain client, never falls back to
  `latest`; `getContractEventsWithRetry` re-throws on the final attempt or any
  non-retryable error (bounded at `RPC_MAX_ATTEMPTS`).
- **HTTP indexer** (`frontend/src/lib/indexer/http.ts`): single timed fetch, validates
  and drops cross-chain/malformed rows — no retry amplification.
- **Probe harnesses** (`scripts/probe-bot-rpc*.py`): evidence-gathering tools (not an
  app hot-path); bounded, transient-only retries, semantic errors never retried.

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

**Historical 2026-10-14 run:** none were observed. **2026-10-15 review:** STOP-11
triggered during source-level adversarial review, then was corrected and regression
tested in `a149a0d8100e8dd88b087ff5d80aaa530db5e46a`. No network transaction was involved.

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
| 10 | clear | `logQueryChunkSizeFor` enforces the BOT-recommended 2,000-block ceiling on 968/677; no unbounded range |
| 11 | **triggered, resolved** | message matching could retry a permanent typed RPC error if its text contained 429/502/503/504; typed classification + regression tests now reject it. Retry remains read-only and bounded; transaction submission is not retried |
| 12 | clear | builds + 130 tests pass under 0.8.26 + cancun (Cancun now BOT-confirmed) |
| 13 | clear | 2-conf is BOT's confirmed *receipt count*, not finality; 12-depth app-side; no reorg/finality guarantee assumed |
| 14 | clear | no opcode/precompile guarantee assumed |
| 15 | clear | language scan found no affirmative "audited/approved/production-ready" |

**Separate from the stop conditions:** the fresh on-chain *write* arm was **not
performed** because its precondition (three funded burner testnet keys) is not met
here. That is a recorded precondition-not-met, not a stop-condition trip, and nothing
was fabricated to stand in for it. See `docs/evidence/FRESH_TESTNET_RUN_BLOCKED.md`.
To unblock, supply three funded **testnet** keys + `CONFIRM_BOT_968_DEPLOY=BOT-968`
and run `scripts/validate-bot-968.py` (which refuses any chain ≠ 968).

## 14. BOT-side status (confirmed vs still open)

Source for the confirmed items: `docs/evidence/BOT-ENGINEERING-GUIDANCE-2026-10-14.md`
(Cisco guidance relayed by Leon, 2026-10-14).

### Confirmed by BOT engineering

1. **eth_getLogs:** recommended query range **2,000 blocks/request**; **no** configured
   rate limit reported. NexEscrow now *enforces* the 2,000-block ceiling on 968/677
   (`rpcPolicy.ts`), rather than merely defaulting to it.
2. **Receipt confirmations:** **2 blocks** on both Bohr 968 and BOT 677. Encoded as
   `writeReceiptConfirmations = 2`. **This is a confirmation count, not a finality or
   reorg guarantee.**
3. **EVM target:** **Cancun**. The repo already targets `evm_version = "cancun"` and
   stays pinned to **Solidity 0.8.26** — Cisco's 0.8.28 example was explicitly *not*
   established as a required minimum.

### Still open / not yet confirmed by BOT

1. **Retry/backoff:** no BOT-specific retry recommendation. NexEscrow's bounded
   3-attempt transient-only retry (`rpcPolicy.ts`) is an **application policy**, not BOT
   guidance.
2. **Reorg / finality:** no reorganisation handling, finality guarantee, or recommended
   indexing-safety depth **beyond** the 2-block receipt count. Our 12-block
   `indexingSafetyDepth` is a conservative **application** choice until BOT advises.
3. **Cancun opcode/precompile limitations:** not supplied. We assume only the subset of
   EVM behaviour actually exercised by the existing deployment and the test suite.

## 15. Explicit limitations (mandatory)

- Validation is **Bohr 968 testnet only**.
- **BOT 677 remains disabled** — not deployed, not enabled, not production ready, not
  selectable for normal execution.
- **2 receipt confirmations are BOT's confirmed receipt count, NOT a reorg/finality
  guarantee.**
- **12-block indexing depth is a NexEscrow application-side safety choice**, not BOT
  policy; it stands until BOT provides reorg/finality guidance.
- The deterministic + read-only validation proves **application behaviour** and
  **observations of the existing Bohr deployment**. It does **not** prove network
  finality, reorg impossibility, universal RPC availability, or opcode/precompile
  compatibility beyond what was actually exercised.
- This validation is **not a security audit** (the contract is **UNAUDITED**).
- This validation is **not production-readiness approval**.
- This validation is **not ecosystem-support / funding approval**.
- This validation is **not mainnet approval**.
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
policy appear in this document. Anything not verified is labelled as unexecuted,
application policy, measured behaviour, or awaiting BOT guidance.*

## 16. Decision boundary and evidence classes (15 October 2026)

| Class | Meaning in this plan |
|---|---|
| **BOT guidance** | Cisco guidance relayed by Leon: 2,000-block maximum recommended log window, 2 receipt confirmations on 968/677, and Cancun target. "No configured rate limit" is a reported configuration, not unlimited-capacity assurance. |
| **Measured behaviour** | A timestamped observation of an endpoint or the existing Bohr deployment; not a network guarantee. |
| **Application policy** | NexEscrow's 12-block indexing safety depth and three-total-attempt transient read retry. BOT has not endorsed either value. |
| **Awaiting BOT guidance** | Retry/backoff recommendation, reorganisation/finality guarantee or indexing depth, and Cancun opcode/precompile limitations. Absence of guidance must be stated explicitly. |
| **Unexecuted proposal** | Any future stateful Bohr run or chain-677 step. It is not evidence that the result will pass. |

## 17. A — checks possible now on local tooling / Bohr 968

Existing read-only Bohr evidence is adequate for A2–A4. Do not spend test funds only
to produce newer-looking hashes. A fresh stateful run (A6) remains unexecuted unless
Rishidar explicitly supplies the established test setup.

### A1 — repository, artifact and guard validation

- **Purpose:** prove the reviewed code builds; the contract artifact remains Solidity
  0.8.26 + Cancun; the 2,000-block cap is enforced; receipt and indexing policies are
  separate; permanent RPC errors are not retried; and 677 remains fail-closed.
- **Network / exact configuration:** local only; Foundry simulates chain IDs. Frontend
  mainnet opt-in unset. No RPC write and no signer.
- **Prerequisites / responsible party:** Rishidar; review SHA, locked dependencies,
  repository-supported Foundry, Node and pnpm.
- **Command/procedure:** run §19, including both BOT-677 chain-safety assertions.
  Inspect artifact metadata for solc `0.8.26`, optimizer 200, via-IR and Cancun.
- **Expected result / evidence:** all commands exit 0; the typed `RpcRequestError`
  regression is non-retryable; offered chains omit 677 without opt-in. Capture UTC
  start/end, SHA, tool versions and full output.
- **Pass/fail threshold:** pass only on zero failed checks and exact policy values.
- **Stop condition:** any build/test failure, default mainnet selection, permanent-RPC
  retry, or artifact-setting mismatch.
- **Cleanup/recovery:** no network cleanup. Do not change policy to hide a failure.

### A2 — chain identity and exact deployment provenance (read-only)

- **Purpose:** bind evidence to Bohr 968 and the intended historical deployment.
- **Network / exact configuration:** `https://rpc.bohr.life`; chain `968`; contract
  `0x6448668ae9cbbc41617c2bd5e4f29279320a2700`; deployment block `26178651`.
- **Prerequisites / responsible party:** Rishidar; reachable RPC; no private key.
- **Command/procedure:** `cast chain-id --rpc-url https://rpc.bohr.life`, then
  `python3 scripts/verify-bot-968-evidence.py --rpc-url https://rpc.bohr.life`.
- **Expected result / evidence:** chain 968; runtime bytecode hash
  `0x7fba19dd52ec2caff42086cc4af9f342caed5564fc1240557e779e1353ea59a7`;
  deployment and eight lifecycle receipts status 1; event identities match. Capture
  full verifier output with UTC timestamps.
- **Pass/fail threshold:** every verifier check passes and address/hash/block match.
- **Stop condition:** wrong chain/address, bytecode mismatch, missing receipt, changed
  event identity, or unexpected RPC/EVM behaviour.
- **Cleanup/recovery:** none; read-only.

### A3 — settlement asset, roles and permissions (read-only)

- **Purpose:** state the tested asset and authority model without generalising it.
- **Network / exact configuration:** existing Bohr contract. Tested asset is native BOT,
  represented by `0x0000000000000000000000000000000000000000`; frontend uses
  18 decimals. This is tested application configuration, not support for every asset.
- **Prerequisites / responsible party:** Rishidar verifies evidence. BOT's technical
  owner identifies any canonical ERC-20 intended later. No ERC-20 is in this plan.
- **Command/procedure:** inspect `deployment.json`, `direct-state.json` and balance
  snapshots; use the verifier to read owner, fee recipient and agreement roles.
- **Expected result / evidence:** manifest and chain roles match; only buyer funds and
  approves, either party disputes, and named arbiter resolves. The historical owner
  key was discarded, so this is an inert validation artifact, not a service.
- **Pass/fail threshold:** exact role/address match and no unexplained authority.
- **Stop condition:** asset/decimal mismatch, role mismatch, unknown wallet control,
  or any need to treat an unconfirmed ERC-20 as supported.
- **Cleanup/recovery:** none. On mismatch, keep the deployment/frontend read-only.

### A4 — funding, release, arbitration refund, fees and conservation

- **Purpose:** re-verify previously executed economic paths without new transactions.
- **Network / exact configuration:** existing Bohr agreements 0 and 1; native BOT.
- **Prerequisites / responsible party:** Rishidar; committed evidence plus RPC.
- **Command/procedure:** run A2's verifier. Agreement A covers funding and two releases.
  Agreement B covers funding, seller dispute and arbiter resolution at 6000 buyer bps.
  The 0.06 BOT buyer payout is the tested refund path. There is no standalone refund
  of a funded active agreement; `cancelBeforeFunding` moves no principal.
- **Expected result / evidence:** 0.2 BOT funded; 0.1 BOT released gross; 0.1 BOT
  dispute gross split; accrued fees equal contract balance; principal loss 0 wei;
  both agreements Completed.
- **Pass/fail threshold:** exact wei conservation and state/event agreement.
- **Stop condition:** unexpected status, balance discrepancy, wrong fee, unauthorized
  role action, or missing/duplicate/inconsistent event.
- **Cleanup/recovery:** none; never send new funds to the inert instance.

### A5 — frontend/indexer consistency, bounded polling and recovery

- **Purpose:** prove UI policy matches chain state and recovery cannot expose unsafe or
  duplicate events.
- **Network / exact configuration:** Bohr 968 and exact contract/start block above;
  2,000 blocks/query; 12-block application indexing depth; two receipt confirmations;
  three total read attempts for allowlisted transient errors.
- **Prerequisites / responsible party:** Rishidar; frontend and read-only RPC.
- **Command/procedure:** run frontend checks in §19. At the next browser evidence
  capture, record every log range and event ID, reload retaining local storage, then
  clear `nexescrow:logscan:v1:968:*` and reload. Compare all three sets with the
  verifier's 11-event set. The scanner intentionally full-replaces from deployment on
  restart; its persisted checkpoint is an observability hint, not a skip cursor.
- **Expected result / evidence:** no range exceeds 2,000; a deployment newer than the
  safe head stays pending; all loads converge to one deduplicated identity/state set;
  permanent RPC errors fail immediately; transient reads stop after three attempts.
  Capture network export, checkpoints and identity comparison.
- **Pass/fail threshold:** exact identity equality, no unsafe latest fallback, and no
  retry of any state-changing operation.
- **Stop condition:** duplicate/missing/inconsistent events, unbounded range,
  checkpoint skip, latest fallback, permanent-error retry, or UI/chain mismatch.
- **Cleanup/recovery:** clear cache/checkpoint and rescan from deployment. Keep UI
  read-only if reconciliation does not converge.

### A6 — optional fresh Bohr write cycle (unexecuted)

- **Purpose:** new stateful evidence only if reviewers reject the existing evidence.
- **Network / exact configuration:** Bohr 968; established harness uses two native BOT
  agreements totalling 0.2 test BOT (0.1 release + 0.1 dispute).
- **Prerequisites / responsible party:** Rishidar supplies three new minimally funded
  Bohr-only wallets and `CONFIRM_BOT_968_DEPLOY=BOT-968`. None are present now.
- **Command/procedure:** follow `FRESH_TESTNET_RUN_BLOCKED.md`; silently enter keys and
  run `validate-bot-968.py` into a new dated directory. It verifies 968 before key use
  and does not retry `cast send` transaction submission.
- **Expected result / evidence:** new manifest, receipts, balances, events, state and
  lifecycle report; every harness check passes.
- **Pass/fail threshold:** exact conservation and all checks pass.
- **Stop condition:** any §18 hard stop, insufficient test funds, or ambiguous wallet
  control.
- **Cleanup/recovery:** unset keys; reconcile test assets; mark deployment
  validation-only and remove it from frontend config. No fresh run occurred here.

## 18. B — proposed future chain-677 validation (unexecuted and gated)

**Decision:** chain 677 stays disabled. No customer funds, deployment, transaction,
frontend enablement or mainnet validation occurs until B0 is agreed in Discussion #2.
A successful future test would not establish universal finality, network guarantees,
a security audit or production clearance.

### B0 — agreement gate

- **Purpose:** close decision inputs before any state-changing mainnet command.
- **Network / exact configuration:** chain 677; no endpoint contact needed.
- **Prerequisites / responsible party:** BOT technical owner supplies or explicitly
  declines to supply retry/backoff guidance, reorg/finality guidance and Cancun
  opcode/precompile limitations. Rishidar approves application assumptions and steps.
  Lucy's review is communication review, not BOT network authority.
- **Command/procedure:** record each answer/absence and accepted assumption in
  Discussion #2; obtain explicit Rishidar approval. Silence is not approval.
- **Expected result / evidence:** dated decision names every assumption and owner.
- **Pass/fail threshold:** every open item is answered or expressly accepted as an
  application-owned risk by the responsible party.
- **Stop condition:** missing approval, unsupported production dependency, or material
  unresolved finality/EVM assumption.
- **Cleanup/recovery:** remain disabled.

### B1 — preflight identity and endpoint check

- **Purpose:** prove the intended mainnet before artifact/funding work.
- **Network / exact configuration:** chain 677; candidate RPC
  `https://rpc.botchain.ai`; read-only.
- **Prerequisites / responsible party:** B0 passed; BOT owner confirms endpoint;
  Rishidar executes.
- **Command/procedure:** `cast chain-id --rpc-url "$BOT_677_RPC_URL"`; record block and
  client response; make one <=2,000-block read-only log query only if guidance permits.
- **Expected result / evidence:** exact chain 677 and expected endpoint behaviour with
  full request/response and UTC timestamps.
- **Pass/fail threshold:** exact identity and no unexpected RPC/EVM behaviour.
- **Stop condition:** wrong chain, endpoint ambiguity, unexpected RPC/EVM response, or
  query outside agreed behaviour.
- **Cleanup/recovery:** unset RPC variable; no state change.

### B2 — exact artifact, asset, roles, funding and exposure manifest

- **Purpose:** remove all configuration ambiguity before deployment.
- **Network / exact configuration:** chain 677. Artifact must name repository SHA,
  source/bytecode hash, Solidity version, optimizer/via-IR, Cancun target and
  constructor args. Asset must be native BOT or one exact token address with decimals
  and measured transfer behaviour.
- **Prerequisites / responsible party:** Rishidar names team-controlled deployer,
  owner, fee recipient, buyer, seller and arbiter and their controllers. BOT confirms
  any asset/address/funding information it owns. Rishidar sets maximum exposure and
  fee policy; this plan invents neither.
- **Command/procedure:** review a complete manifest. For ERC-20, first perform read-only
  `decimals`, `symbol`, `balanceOf` and bytecode checks.
- **Expected result / evidence:** no placeholder, custody ambiguity, unknown asset or
  unspecified amount remains.
- **Pass/fail threshold:** exact values and named controllers/approvers for every role.
- **Stop condition:** asset/permission mismatch, missing wallet control, customer
  funds, missing approval, or exposure above agreed maximum.
- **Cleanup/recovery:** reject incomplete manifest and remain disabled.

### B3 — guarded dry run and pre-deployment review

- **Purpose:** verify bytecode, roles, gas estimate and guard without broadcasting.
- **Network / exact configuration:** 677; generic deploy script only. Bohr wrapper must
  continue rejecting 677.
- **Prerequisites / responsible party:** B0–B2 passed; Rishidar controls deployer;
  approved gas; reviewed 677 evidence harness exists.
- **Command/procedure:** prove generic script fails with `ALLOW_MAINNET_DEPLOYMENT`
  unset. In an approved isolated session only, set it and run `forge script
  script/DeployNexusEscrow.s.sol:DeployNexusEscrow --rpc-url "$BOT_677_RPC_URL" -vvvv`
  without `--broadcast`; compare artifact/constructor/gas with B2.
- **Expected result / evidence:** default refusal and exact simulation; no tx hash.
- **Pass/fail threshold:** guard and dry run pass within agreed exposure/gas limit.
- **Stop condition:** unexpected artifact/address, revert, unsupported opcode,
  missing approval or exceeded limit.
- **Cleanup/recovery:** unset opt-in/signer; confirm no broadcast; keep 677 absent from
  frontend config.

### B4 — minimal stateful validation (future proposal; no action now)

- **Purpose:** if separately approved, exercise deployment, funding, normal release,
  dispute and arbiter-directed buyer refund without customer funds.
- **Network / exact configuration:** exact B2 manifest and amount only. No amount or
  fee is specified here because none is agreed.
- **Prerequisites / responsible party:** Rishidar authorizes; BOT supplies prerequisites
  it owns; exact team wallets are funded within cap; a reviewed 677-only harness
  refuses other chains and never blindly resubmits writes.
- **Command/procedure:** deploy once and source-verify; create/fund one release agreement
  and one dispute agreement; buyer releases, named party disputes, named arbiter
  resolves using pre-agreed split. Wait agreed receipt count. Record wallet-control
  linkage, receipts, events and direct state.
- **Expected result / evidence:** only agreed asset/amount moves; state/events reconcile;
  refund means arbiter-directed buyer payout, not a nonexistent standalone refund.
- **Pass/fail threshold:** every receipt succeeds; exact roles; asset conservation at
  smallest units; exposure never exceeds cap.
- **Stop condition:** any shared hard stop, revert, duplicate submission, unidentified
  signer or exceeded cap.
- **Cleanup/recovery:** stop writes; reconcile principal/payouts/fees; withdraw only as
  pre-approved; record residuals and mark deployment validation-only.

### B5 — frontend/indexer reconciliation and disable-again proof

- **Purpose:** prove visibility without converting a test into production enablement.
- **Network / exact configuration:** B2/B4 deployment; 2,000-block ceiling; receipt and
  indexing values exactly as agreed at B0.
- **Prerequisites / responsible party:** B4 passed; Rishidar uses a non-customer,
  access-limited validation build.
- **Command/procedure:** compare UI, bounded scan, direct reads and canonical event IDs;
  restart/replay as A5. Then remove/unset `NEXT_PUBLIC_ALLOW_MAINNET`, chain 677,
  address/deploy block and signer variables; rebuild and run fail-closed checks.
- **Expected result / evidence:** exact state/accounting match, then a build where 677
  is neither selected nor offered.
- **Pass/fail threshold:** zero event discrepancy and positive disable-again evidence.
- **Stop condition:** UI/chain mismatch, replay divergence, violated finality
  assumption, unsupported dependency, or failure to disable.
- **Cleanup/recovery:** keep 677 disabled; archive evidence; reconcile test assets and
  residual contract balance. A non-upgradeable contract cannot be deleted; disabling
  means removing app/config use and accepting no funds.

### Shared hard stop conditions

Stop immediately on wrong chain or contract address; unresolved asset/permission
mismatch; unexplained balance discrepancy; duplicate, missing or inconsistent indexed
events; unexpected RPC/EVM behaviour; violated finality assumption or unsupported
production dependency; missing approval; or exceeded funding/gas/exposure limit.
Preserve partial evidence, send no transaction merely to make a run look complete, and
reconcile only through the pre-agreed recovery procedure.

## 19. Current local verification commands for the next evidence head

```bash
git rev-parse HEAD
git diff --check

cd contracts
forge fmt --check
forge build
forge test
FOUNDRY_PROFILE=ci forge test

cd ../frontend
pnpm lint
pnpm typecheck
pnpm test
EXPECT_CHAIN_ID=968 pnpm check:chain-safety
NEXT_PUBLIC_CHAIN_ID=677 EXPECT_CHAIN_ID=968 pnpm check:chain-safety
NEXT_PUBLIC_CHAIN_ID=677 NEXT_PUBLIC_ALLOW_MAINNET=true EXPECT_CHAIN_ID=677 pnpm check:chain-safety
pnpm check:finality-policy
pnpm build

cd ..
python3 -m pytest tests/
python3 scripts/verify-bot-968-evidence.py --rpc-url https://rpc.bohr.life
```

The explicit-opt-in 677 chain-safety command is a local configuration assertion only;
it sends no RPC write and does not authorize deployment or frontend enablement.

## 20. Honest checkpoint

- **Ready now:** scoped retry fix, local/Bohr plan, existing Bohr evidence, and draft
  communications after repository-prescribed verification.
- **Under Rishidar's control:** review/approve plan and drafts, decide whether optional
  fresh Bohr evidence is useful, and keep 677 disabled.
- **Awaiting BOT/Cisco:** retry/backoff recommendation or explicit absence;
  reorg/finality guidance or explicit absence; Cancun opcode/precompile limitations or
  explicit absence.
- **Next measurable review point:** integration head pushed and matching CI green;
  after that, receipt of BOT answers and agreement of B0. No BOT response date is
  promised.
