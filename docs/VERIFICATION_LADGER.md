# VERIFICATION_LADGER.md — what is actually verified about NexEscrow, and at which layer

**Status:** documentation only. No contract, script, frontend or CI change.
**Branch:** `docs/verification-ladder-20261022` (base: `origin/master` @ `7183779`)
**Written:** 2026-10-22 · **Reviewer:** adversarial reconciliation pass

**Why this file exists.** NexEscrow's status is routinely summarised in one
of two lossy ways: *"it's done, CI is green"* or *"it's all still in a draft"*.
Both are wrong, and both mislead in opposite directions. The truth is layered,
and the layers are **not** interchangeable.

This file names the layers, states precisely what has been demonstrated at each
one, and marks the things that are commonly conflated.

---

## 1. The six layers

| # | Layer | Question it answers | NexEscrow's state |
|---|---|---|---|
| 1 | **Design** | Is the protocol specified? | **Done** — `SPEC.md`, `docs/THREAT_MODEL.md`, `docs/ARBITRATION_MODEL.md`, Demo 1 hardening spec `07c6eb0` |
| 2 | **Code** | Is it implemented? | **Implemented and locally verified** — 130 Foundry tests, 35 frontend tests, 6 script tests, all recorded on the validated tree `7d1832b` (PR #1 head has since advanced to `24cc8c8`) |
| 3 | **CI** | Does it build green on every commit? | **Green** — 16 deploy/status events on PR #1, latest 2026-10-17T15:46:54Z; Demo 1 PRs #4–#9 all CI-green per the 2026-10-12 closure pass |
| 4 | **Review** | Has someone independent read it? | **NO** — PR #1 has **zero human reviews**. All 7 review events are 6× CodeRabbit (bot, `COMMENTED`) + 1× the owner. `reviewDecision` is empty. |
| 5 | **Merge** | Is it in the default branch? | **NO** — `master` is still at `7183779` (2026-10-05). PR #1 is open. Demo 1 PRs #4–#10 are open and stacked. |
| 6 | **Deployment** | Does it exist on a chain? | **Testnet only** — one instance on BOT Bohr **968**. **No mainnet deployment, ever.** No mainnet transaction broadcast. |

**The single most important sentence in this file:**

> Layers 1–3 and 6 are strong and evidenced. **Layer 4 is empty.** Layers 5
> and 6 are gated on decisions that are not code problems.

A green CI badge on an open draft that nobody has reviewed is worth exactly
what it says: **the code compiles and the tests pass**. It is not evidence of
correctness, and it is not evidence of readiness.

---

## 2. Layer 4 — the review gap, stated precisely

**This is the layer where NexEscrow is genuinely weak, and it is weak in a way
that no amount of additional testing fixes.**

| PR | Title | State | Draft | Human reviews | Notes |
|---|---|---|---|---|---|
| #1 | feat: add BOT Chain integration and Bohr 968 validation | OPEN | **yes** (draft) | **0** | base `master`; head `24cc8c8`; `MERGEABLE` / `CLEAN`; 7 review events, all bot or owner |
| #4 | Demo 1 tranche A — NexEscrowCore signed bilateral intent | OPEN | no | 0 | base `whitepaper/demo-1-hardening` |
| #5 | Demo 1 tranche B — funding, in-order release, dispute liveness | OPEN | no | 0 | base tranche A |
| #6 | Demo 1 tranche C — resolver modules, evidence, appeal | OPEN | no | 0 | base tranche B |
| #7 | Demo 1 tranche D — user-consented bilateral migration | OPEN | no | 0 | base tranche C |
| #8 | Demo 1 tranche E — x402 / AP2 / ERC-8004 metadata adapters | OPEN | no | 0 | base tranche D |
| #9 | Demo 1 tranche F — production ingestion engine | OPEN | no | 0 | base tranche E |
| #10 | signed-intent interoperability vectors | OPEN | **yes** (draft) | 0 | base tranche F (opened 2026-10-22) |

Two things worth stating explicitly, because both have been asserted or
implied in correspondence:

1. **Leon was asked for a review on 2026-10-11 and has not given one.** No
   review, no comment, and no response is recorded on the PR from any
   non-owner, non-bot account. **The review request is still outstanding —
   and, as §2.1 shows, it was mis-aimed when it was sent.**
2. **PR #1 was un-drafted on 2026-10-11T01:26:17Z and converted back to draft
   on 2026-10-17T16:15:57Z.** Any status summary that says "ready for review"
   is describing a state that existed for six days in October and does not
   describe the current state. The 2026-10-11 notes are accurate *about the
   11th*; the repository is now in a different state.

### 2.1 The review request points at the wrong repository — two times out of three

This was found by re-deriving the three named locations from the git objects
rather than trusting the note.

`NEXESCROW_LEON_UPDATE.md` (2026-10-11, 08:10, naming head `7d1832b`) asks
for a read of three places:

| # | Location named in the request | Where it actually is |
|---|---|---|
| 1 | `ScopeValidator._pattern_matches` — host/port/path matching | **Morphia.** `apps/api/tests/test_zz_scope.py` in `~/morphia-work/Morphia-alpha-stack`. Python/FastAPI. |
| 2 | `verify_finding`'s separation-of-duties logic | **Morphia.** `apps/api/app/routers/findings.py`. Python/FastAPI. |
| 3 | `_payOut`'s native-transfer failure handling | **NexEscrow.** `contracts/src/NexusEscrow.sol`. ✓ |

**Verified:** `git grep` for `ScopeValidator`, `_pattern_matches` and
`verify_finding` returns **zero hits** across the entire repository at every
commit on `feat/botchain-integration` — `811afd5`, `0b03e46`, `0887126`,
`df6ac75`, `7d1832b` and `24cc8c8` — and also at the Demo-1 tranche F head.
They are not renamed functions. They are code from a different project, in a
different language, that this request never pointed at.

**What this means.** A reviewer who opened NexEscrow to follow the request
would have found nothing at two of the three named locations. It is a
reasonable, evidence-supported explanation for why the review never came back
— and it is **not** a reason to leave the request as it stands.

**The correct NexEscrow pointers**, for whoever reissues the request:

| The question that was asked | The NexEscrow location that actually answers it | Layer |
|---|---|---|
| *host/port/path matching, narrower wildcard grammar* | **There is no URL/host/path matching in NexEscrow.** The nearest analogue is address-scoped authority: `NexEscrowCore.ResolutionPolicy` (`contracts/src/NexEscrowCore.sol:107-115`) and its validation. The original question is a Morphia question and should be sent to a Morphia reviewer. | Demo 1, PR #4+ |
| *separation of duties in verification* | **`NexEscrowCore._validatePolicy`** (`contracts/src/NexEscrowCore.sol:724-752`): `primaryResolver != buyer && != seller`; and where `appealWindow > 0`, `appellateResolver != address(0) && != buyer && != seller && != primaryResolver`. This is a genuine separation-of-duties check — and it lives on the **Demo-1 stack**, not on PR #1. | Demo 1, PR #4+ |
| *native-transfer failure handling for a seller that rejects value* | **`NexusEscrow._payOut`** — valid as named. | PR #1 |

**A second, smaller point.** Two of the three questions resolve to code that is
**not on PR #1** but on the Demo-1 stack (#4 and up). PR #1 cannot be reviewed
as a self-contained unit for those questions, because the code that answers
them does not exist on it. The review request needs to say which stack each
question belongs to.

**Recommended action (not taken here).** Reissue the review request with the
corrected pointers, split by stack, before asking again. Do not merge on the
strength of a request that was not answerable as written.

---

## 3. Layer 5 — the dependency stack, and why it must not be reordered

The stack is a single chain. Each PR's base is the previous PR's head branch:

```
master  (7183779, 2026-10-05)
  └─ #1  feat/botchain-integration            → master        (draft, open)
       └─ whitepaper/demo-1-hardening          (07c6eb0, 2026-10-11)
            └─ #4  feat/demo1-tranche-a-core   → whitepaper/demo-1-hardening
                 └─ #5  tranche-b-liveness     → tranche-a
                      └─ #6  tranche-c-resolver → tranche-b
                           └─ #7  tranche-d-migration → tranche-c
                                └─ #8  tranche-e-adapters  → tranche-d
                                     └─ #9  tranche-f-indexer → tranche-e
                                          └─ #10 intent-interoperability → tranche-f
```

**Verified:** `origin/feat/botchain-integration` is an ancestor of
`origin/whitepaper/demo-1-hardening`; the merge-base is `24cc8c8`, which is
exactly PR #1's current head. `git rev-list --left-right --count` reports
`0  1` — the Demo-1 branch is one commit ahead of PR #1's head and nothing
behind.

**Consequences that constrain every change to this repository:**

- PR #1 **must merge first**. Every Demo 1 PR inherits from it.
- Demo 1 PRs **must merge in order** #4 → #5 → #6 → #7 → #8 → #9 → #10, each
  into its predecessor's branch, and only then the accumulated
  `whitepaper/demo-1-hardening` branch into `master`.
- **Rebasing or retargeting any PR breaks the chain** and silently changes
  what each PR's diff means.
- Merging the chain is an **owner decision**, not an engineering one. It is
  gated on layer 4.

**A note on `main`.** The repository has two long-lived branches. `master` is
the default branch and the production baseline; `main` is a superseded
prototype frozen at 2026-06-21. Their merge-base is `bd7d48f` — the initial
commit. **They are not unrelated histories.** Anyone auditing from a default
shallow clone will reach the wrong conclusion; the local clone's fetch refspec
and shallow history were corrected on 2026-10-11 for exactly this reason.

---

## 4. Layer 6 — deployment: what exists and what does not

### Exists

- **One** contract instance on BOT Bohr **chain 968** (testnet).
- Runtime bytecode 6,309 B; `keccak256` of a fresh local build's runtime equals
  the recorded `bytecodeHash`; `eth_getCode` returns 6,309 B.
- Two completed lifecycles exercised, events and states confirmed, fees
  accrued, conservation exact: funded 0.2 = released 0.1 + disputed 0.1.
- Live `accruedFees(0x0)` equals the escrow's native balance — zero principal
  stranded.

### Does not exist

- **No mainnet deployment.** BOT 677 is not deployed, not enabled, not
  reachable by default.
- **No mainnet transaction has ever been broadcast** in this project.
- The recorded mainnet evidence is a **dry run only**.
- The contract carries `auditStatus: UNAUDITED`.

### The guard, and what it is worth

The mainnet guard is **tested**, not merely asserted — this was a real gap
closed on 2026-10-11 (`0887126`). Before that change, `forge coverage` reported
**0.00%** on both deployment scripts (`0/30` and `0/20` executable lines),
meaning the "never deploy to mainnet by accident" control had no automated
proof at all.

The guards could not be tested through `run()`: `vm.setEnv` mutates
process-global state, Foundry has no `unsetEnv`, parallel threads race, and the
identical command returned 0, 1, 4, 5, 8 and 10 failures on consecutive runs.
**A non-deterministic safety test is worse than none.** The policy was factored
into `script/DeployPolicy.sol` — `pure`, parameterised, no environment — and
both scripts now read the environment and delegate.

| Script | Before | After |
|---|---|---|
| `DeployNexusEscrow.s.sol` | 0.00% (0/30) | **95.83% lines, 100% funcs** |
| `DeployNexusEscrowBOT.s.sol` | 0.00% (0/20) | **100.00% lines, 100% funcs** |
| `DeployPolicy.sol` | new | **100% lines / branches / funcs** |
| `src/NexusEscrow.sol` | 98.56% | 98.56% (untouched) |

No behaviour changed: every revert string is byte-identical, condition
ordering is unchanged, and both chain-specific mainnet warnings still print
verbatim so `docs/evidence/mainnet-guard-677.log` stays accurate.

---

## 5. Things that are commonly conflated — and must not be

| Conflated | Actually distinct |
|---|---|
| "CI is green" | "CI is green" ≠ "reviewed" ≠ "merged" ≠ "deployed". Four separate claims. |
| "Testnet success is production readiness" | Every lifecycle, dispute, fee and conservation claim comes from Bohr 968. **Testnet success is not production readiness.** |
| "The arbiter is neutral" | The arbiter is **buyer-chosen** and not verifiably independent. The contract enforces only `arbiter != buyer && arbiter != seller`. A colluding buyer and arbiter can award 100% of a disputed milestone to the buyer. |
| "The milestone was delivered" | The contract settles according to the **buyer's approval** and the **arbiter's ruling**. It does not and cannot verify real-world delivery. That is the arbiter's judgment, made authoritative by the contract. |
| "No timeout release" | If both parties go unresponsive, funds stay locked. This is a **known, documented limitation**, not an oversight. |
| "ERC-20 supported" | Fee-on-transfer tokens are rejected at `fund`; rebasing tokens are documented as unsupported; blocklisted or pausable tokens are not defensible at the escrow layer. |
| "Deployed" | One testnet instance. `mainnet` has never been touched. |

---

## 6. The three questions that are still open — for the network, not the code

These were raised on 2026-10-11 and have **not** been answered. They are
BOT-chain questions, so they are not answerable by measurement alone, and the
repository is careful not to pretend otherwise.

1. **Log-query and retry guidance.** The frontend polls a bounded block
   window. BOT's recommended query pattern and retry/backoff behaviour is
   unsettled.
2. **Finality policy.** The current policy — 2 write-receipt confirmations,
   12-block indexing safety depth — is **deliberately provisional** and is
   explicitly *not* a claim about what BOT recommends in production.
3. **Cancun support.** `foundry.toml` pins `evm_version = "cancun"` with a
   documented fallback to `paris`. Whether BOT supports Cancun, and with what
   finality characteristics, still needs confirming.

Empirical Bohr observations are recorded in the repository and are labelled as
**observations only**. They are not BOT Chain policy and are not a guarantee.

---

## 7. Summary for a reader who has five minutes

- The engineering is real: a spec, 130 passing contract tests, a test runner
  for the frontend, a **proven** mainnet guard, and a live testnet instance
  with exact conservation.
- **Nothing has been reviewed by a human.** That is the gap.
- **Nothing has been merged.** `master` is five weeks behind the work.
- **Nothing is on mainnet** and the guard is designed to keep it that way.
- The project is **UNAUDITED** and says so.
- The three named questions from 2026-10-11 are still open and still the
  network's to answer.

None of that is a criticism of the work. It is a description of which claims
the work currently supports.
