# NexEscrow — Threat Model & Escrow State Machine

> Status: **UNAUDITED / TESTNET STAGE.** This document is a security model, not an audit.
> Contract: `contracts/src/NexusEscrow.sol` (Solidity 0.8.26, OpenZeppelin 5.x, non-upgradeable).
> Last updated: 2026-10-08 (BOT Chain integration sprint, branch `feat/botchain-integration`).

This document is written against a specific commit. Any contract change must update it.
It deliberately states where the protocol *fails closed*, where it *depends on an
off-chain actor*, and which states are **impossible by construction** versus merely
**unenforced**.

---

## 1. Actors

| Actor | Description | Trust level |
|---|---|---|
| **Buyer** | Creates the agreement, deposits 100% of the total up front, approves milestone releases. | Counterparty. May be malicious (griefing, selective non-approval, refusing to dispute). |
| **Seller** | Receives milestone payouts as milestones release. | Counterparty. May be malicious (non-delivery, disputing a good milestone). |
| **Arbiter** | Chosen at creation by the buyer. Sole resolver of a disputed milestone. | Trusted-but-not-verified. Can award 0–100% of a disputed milestone to the buyer, with fees only on the seller side. Must be a third party distinct from buyer and seller. |
| **Owner / admin** | `Ownable2Step` owner. Can pause/unpause, set protocol fee (≤ 10%), change fee recipient, transfer ownership (2-step). | Trusted for availability and fee configuration only. **Cannot move escrow principal, cannot resolve disputes, cannot rewrite agreements.** |
| **Fee recipient** | Receives accrued protocol fees via `withdrawFees`. | Trusted only for receiving fees. Can be changed by owner; accrued-but-unwithdrawn fees follow the *current* recipient. |
| **Anyone** | After a funding deadline has passed, any address can cancel an *unfunded* agreement. | Untrusted. |

There is no upgrade admin, no proxy, no emergency fund withdrawal, and no privileged
function that transfers a participant's escrowed principal.

---

## 2. Assets

| Asset | Representation | Movement |
|---|---|---|
| Native asset (NEX on Nexus, BOT on BOT Chain, ETH on local anvil, …) | `token == address(0)` | `msg.value` in `fund`; `.call{value:}` out on payout. |
| ERC-20 | token address | `SafeERC20.safeTransferFrom` in `fund`; `safeTransfer` out on payout. |

The contract holds no other value. `accruedFees[token]` is an accounting claim on tokens
already inside the contract (or native already deposited).

---

## 3. Agreement & milestone state machines

### 3.1 Agreement states

```
                      createAgreement
  (nonexistent) ───────────────────────▶ AwaitingFunding
        │                                    │        │
        │           fund (buyer, full amt)   │        │ cancelBeforeFunding
        │                                    ▼        │  (party any time, or
        │                                  Active     │   anyone after deadline)
        │                                    │        ▼
        │                    last milestone │     Cancelled  (terminal)
        │                    released/resolved
        │                                    ▼
        └──────────────────────────────▶ Completed (terminal)
```

* `AwaitingFunding` — agreement exists, buyer has not deposited. Cancellable by either
  party at any time; by any address once `fundingDeadline` has passed (a deadline of `0`
  means "no deadline", so only the parties can ever cancel).
* `Active` — full total deposited. Milestones release strictly in order via
  `approveMilestone` or `resolveDispute`.
* `Completed` — terminal; set exactly when `nextMilestone == milestoneCount`.
* `Cancelled` — terminal; only reachable from `AwaitingFunding`, therefore no funds are
  ever present when it is entered.
* **Paused is not an agreement state.** It is a global contract flag that blocks
  `createAgreement`, `fund`, `approveMilestone`, `raiseDispute`, `resolveDispute`, and
  `cancelBeforeFunding`. It does **not** block `withdrawFees`, `setProtocolFee`,
  `setFeeRecipient`, `pause`, `unpause`, or views.

### 3.2 Milestone states

```
   createAgreement
 (implicit: Pending)
        │
        ├── approveMilestone (buyer) ────▶ Released ──┐
        │                                            ├──▶ (monotonic; terminal per milestone)
        └── raiseDispute (buyer|seller) ─▶ Disputed ──┤
                    │                                │
                    └── resolveDispute (arbiter) ──▶ Resolved
```

Rules enforced by the contract:

* Only the milestone at index `nextMilestone` can be acted on. Earlier milestones are
  already Released/Resolved; later ones are unreachable until `nextMilestone` advances.
* `_advance` increments `nextMilestone` and, on the last milestone, flips the agreement
  to `Completed` and emits `AgreementCompleted`.
* Released/Resolved are terminal per milestone: `approveMilestone` requires `Pending`,
  `raiseDispute` requires `Pending`, `resolveDispute` requires `Disputed`. Double-release
  and double-resolve are impossible.
* A milestone cannot be released out of order, and progress cannot regress.

### 3.3 State-transition table

| # | From | Trigger | Caller | Guard | To | Funds moved |
|---|---|---|---|---|---|---|
| T1 | — | `createAgreement` | anyone (becomes buyer) | not paused; seller ≠ 0, ≠ buyer; arbiter ≠ 0, ≠ buyer, ≠ seller; 1 ≤ milestones ≤ 50; no zero amount; sum ≤ uint128 max; deadline 0 or > now | AwaitingFunding | none |
| T2 | AwaitingFunding | `fund` | buyer | not paused; value == total (native) or allowance (ERC-20) and `msg.value == 0`; deadline not passed | Active | buyer → contract, full total |
| T3 | AwaitingFunding | `cancelBeforeFunding` | party, or anyone after deadline | not paused; deadline passed (for non-parties) | Cancelled | none |
| T4 | Active | `approveMilestone` | buyer | not paused; milestone `nextMilestone` is Pending | Active or Completed | contract → seller (amount − fee); fee accrued |
| T5 | Active | `raiseDispute` | buyer or seller | not paused; milestone `nextMilestone` is Pending | Active (milestone Disputed) | none |
| T6 | Active | `resolveDispute(id, buyerBps)` | arbiter | not paused; buyerBps ≤ 10000; milestone `nextMilestone` is Disputed | Active or Completed | contract → buyer (buyerBps share); contract → seller (rest − fee); fee accrued |
| T7 | any | `pause` / `unpause` | owner | — | (global flag) | none |
| T8 | any | `setProtocolFee` | owner | bps ≤ 1000 | — | none (applies to future agreements only) |
| T9 | any | `setFeeRecipient` | owner | recipient ≠ 0 | — | none (future withdrawals) |
| T10 | any | `withdrawFees(token)` | fee recipient | accruedFees[token] > 0; not paused is **not** required | — | contract → fee recipient |
| T11 | any | `transferOwnership` / `acceptOwnership` / `renounceOwnership` | owner / pending owner | Ownable2Step semantics | — | none |

### 3.4 Impossible / unenforced states

**Impossible by construction** (must remain impossible; invariant-tested):

1. `Completed` with `nextMilestone < milestoneCount` — `_advance` is the only writer.
2. `Cancelled` after any funds were deposited — `cancelBeforeFunding` requires
   `AwaitingFunding`, and `fund` is the only transition into `Active`.
3. A milestone at an index `< nextMilestone` that is still `Pending`.
4. Double release of one milestone; release after dispute; resolve without dispute.
5. Out-of-order milestone action.
6. Principal outflow to the owner, arbiter, or fee recipient — no function routes
   principal to any privileged address (`resolveDispute` pays only buyer/seller;
   `withdrawFees` only ever pays `accruedFees`, which is deducted only from the
   seller-side payout).

**Unenforced / liveness hazards** (documented, not fixed in the core contract):

1. **Silent arbiter.** A disputed milestone is frozen until the arbiter calls
   `resolveDispute`. There is no timeout fallback, by design. If the arbiter is
   non-responsive, the disputed milestone's funds are locked indefinitely.
   *Mitigation: participant-side arbiter selection; a future version may add an
   opt-in timeout that refunds the buyer of the disputed milestone only.*
2. **Both parties want to abandon a funded agreement.** There is no mutual-cancel.
   They must raise a dispute on the current milestone and have the arbiter resolve it
   100% back to the buyer. The remainder of unallocated milestones stays escrowed until
   the same dance is repeated milestone by milestone.
3. **Paused active agreement.** While paused, no agreement path can progress (only
   `withdrawFees` works). Pause is an owner availability lever with a liveness cost.
   It cannot corrupt accounting, but a malicious/compromised owner can freeze all
   agreements; unpausing restores every path.
4. **Native payout to a reverting contract.** `_payOut` uses a plain `.call`; if the
   seller (or a refunded buyer) is a contract that rejects native value, the
   release/resolution reverts and that milestone cannot clear through that path.
   ERC-20 payouts to contracts depend on the token's transfer semantics.
5. **Zero-amount payout paths.** `resolveDispute` skips `_payOut` when an amount is 0,
   so `buyerBps == 10000` (full refund, no fee) and `buyerBps == 0` (full seller award
   minus fee) never attempt a zero-value native call.
6. **Fee-recipient drift.** Changing `feeRecipient` while fees are accrued means the
   new recipient can withdraw previously accrued fees. This is intended (the claim
   belongs to the protocol, not to an address), but it must be disclosed.
7. **Arbiter neutrality is a creation-time check only.** The contract cannot verify that
   an arbiter is independent; it only enforces `arbiter != buyer && arbiter != seller`.
8. **Rebasing / blocklist / pausable tokens** can break payout liveness; the contract
   explicitly rejects fee-on-transfer funding (see §5) but cannot neutralize a token
   that freezes the contract's balance later.

---

## 4. Function-by-function reference

Notation: R = state read, W = state write, X = external call, $ = asset movement.

### 4.1 `createAgreement(seller, arbiter, token, milestoneAmounts, fundingDeadline) → id`

| Field | Detail |
|---|---|
| **Caller** | Any address; becomes `buyer` of the new agreement. |
| **Preconditions** | `whenNotPaused`; `seller != 0 && seller != msg.sender`; `arbiter != 0 && arbiter != msg.sender && arbiter != seller`; `1 <= milestoneAmounts.length <= 50`; every amount `> 0`; sum `<= type(uint128).max`; `fundingDeadline == 0 || fundingDeadline > block.timestamp`. |
| **State read** | `protocolFeeBps`; `nextAgreementId`; `block.timestamp`. |
| **State write** | `nextAgreementId += 1`; new `Agreement`; pushes `Milestone[]`. |
| **External call** | none. |
| **Asset movement** | none. |
| **Event** | `AgreementCreated(id, buyer, seller, arbiter, token, totalAmount, feeBps, fundingDeadline, milestoneAmounts)`. |
| **Failure** | `InvalidAddress`, `InvalidMilestones`, `InvalidAmount`, `DeadlinePassed`, `EnforcedPause`. |
| **Notes** | `feeBps` is **snapshotted** here; later `setProtocolFee` cannot affect this agreement. The emitted `feeBps` equals the stored value. |

### 4.2 `fund(id)` — payable

| Field | Detail |
|---|---|
| **Caller** | Buyer of agreement `id` only (`onlyBuyerOf`). |
| **Preconditions** | `whenNotPaused`, `nonReentrant`; status == `AwaitingFunding`; `fundingDeadline == 0 || block.timestamp <= fundingDeadline`; native: `msg.value == totalAmount`; ERC-20: `msg.value == 0` and allowance sufficient and token balance sufficient; token transfer must deliver exactly `totalAmount` (see §5). |
| **State read** | agreement; token balance delta (hardened path). |
| **State write** | `status = Active`. |
| **External call** | `safeTransferFrom` (ERC-20 only). |
| **Asset movement** | $ buyer → contract, exactly `totalAmount`. |
| **Event** | `Funded(id)`. |
| **Failure** | `WrongState`, `DeadlinePassed`, `NativeValueMismatch`, `UnsupportedTokenBehavior` (fee-on-transfer/under-delivery), SafeERC20 errors, `EnforcedPause`, `ReentrancyGuardReentrantCall`. |
| **Notes** | CEI: status flips before the transfer; `nonReentrant` blocks token-callback reentry. |

### 4.3 `approveMilestone(id)`

| Field | Detail |
|---|---|
| **Caller** | Buyer only. |
| **Preconditions** | `whenNotPaused`, `nonReentrant`; status == `Active`; milestone at `nextMilestone` is `Pending`. |
| **State read** | agreement, milestone, `feeBps` snapshot. |
| **State write** | milestone → `Released`; `nextMilestone++` (or agreement → `Completed` via `_advance`); `accruedFees[token] += fee`. |
| **External call** | native `.call{value:}` or `safeTransfer` to seller. |
| **Asset movement** | $ contract → seller, `amount − fee`. |
| **Events** | `MilestoneReleased(id, idx, amount, fee)`; plus `AgreementCompleted(id)` on the final milestone. |
| **Failure** | `NotBuyer`, `WrongState`, `WrongMilestoneState`, `NativeTransferFailed`, SafeERC20 errors, pause/reentrancy guards. |
| **Notes** | Fee formula: `floor(amount * feeBps / 10000)`; seller receives the remainder, so buyer+seller+fee conserve exactly. |

### 4.4 `raiseDispute(id)`

| Field | Detail |
|---|---|
| **Caller** | Buyer or seller of `id`. |
| **Preconditions** | `whenNotPaused`; status == `Active`; milestone at `nextMilestone` is `Pending`. |
| **State read** | agreement, milestone. |
| **State write** | milestone → `Disputed`. |
| **External call** | none (no reentrancy surface; no guard needed). |
| **Asset movement** | none. |
| **Event** | `DisputeRaised(id, idx, msg.sender)`. |
| **Failure** | `WrongState`, `NotParty`, `WrongMilestoneState`, `EnforcedPause`. |
| **Notes** | One dispute at a time per agreement; the frozen milestone is always `nextMilestone`. |

### 4.5 `resolveDispute(id, buyerBps)`

| Field | Detail |
|---|---|
| **Caller** | Arbiter of `id` only. |
| **Preconditions** | `whenNotPaused`, `nonReentrant`; `buyerBps <= 10000`; status == `Active`; milestone at `nextMilestone` is `Disputed`. |
| **State read** | agreement, milestone, `feeBps` snapshot. |
| **State write** | milestone → `Resolved`; `nextMilestone++` / `Completed`; `accruedFees += fee`. |
| **External call** | up to two payouts (buyer refund, seller net). |
| **Asset movement** | buyer gets `floor(amount * buyerBps / 10000)`; seller gets `amount − buyerAmount − fee`, where `fee = floor((amount − buyerAmount) * feeBps / 10000)`. |
| **Event** | `DisputeResolved(id, idx, buyerBps, buyerAmount, sellerAmount, fee)`; plus `AgreementCompleted` when final. |
| **Failure** | `NotArbiter`, `BpsOutOfRange`, `WrongState`, `WrongMilestoneState`, payout failures, pause/reentrancy guards. |
| **Notes** | Conservation: `buyerAmount + sellerAmount + fee == amount` for every `buyerBps`. Refunds are never taxed. |

### 4.6 `cancelBeforeFunding(id)`

| Field | Detail |
|---|---|
| **Caller** | Buyer or seller; **or any address once `fundingDeadline` has passed.** |
| **Preconditions** | `whenNotPaused`; status == `AwaitingFunding`. |
| **State read** | agreement, `block.timestamp`. |
| **State write** | status → `Cancelled`. |
| **External call** | none. |
| **Asset movement** | none (cannot be reached with funds). |
| **Event** | `AgreementCancelled(id)`. |
| **Failure** | `WrongState`, `NotAuthorized`, `EnforcedPause`. |

### 4.7 `withdrawFees(token)`

| Field | Detail |
|---|---|
| **Caller** | Current `feeRecipient` only. |
| **Preconditions** | `nonReentrant`; `accruedFees[token] > 0`. **Not blocked by pause** (by design: fees must not be hostage to pause). |
| **State read/write** | zeroes `accruedFees[token]`. |
| **Asset movement** | $ contract → current fee recipient, `amount`. |
| **Event** | `FeesWithdrawn(token, to, amount)`. |
| **Failure** | `NotAuthorized`, `NothingToWithdraw`, payout failures. |
| **Notes** | If the fee recipient is a contract that rejects native value, native fees are stuck until `setFeeRecipient` points at a payable address. ERC-20 fees use `safeTransfer`. |

### 4.8 Admin functions

| Function | Caller | Effect | Cannot do |
|---|---|---|---|
| `setProtocolFee(bps)` | owner | sets fee for **future** agreements, `bps <= 1000` | change snapshotted `feeBps` of existing agreements |
| `setFeeRecipient(addr)` | owner | future fee withdrawals go to `addr` | touch principal or historical agreement accounting |
| `pause()` / `unpause()` | owner | global availability switch | move funds, resolve disputes, alter state |
| `transferOwnership` / `acceptOwnership` / `renounceOwnership` | owner / pending owner | 2-step ownership handoff | bypass any guard above |

### 4.9 Views

`agreements(id)`, `getMilestones(id)`, `getMilestone(id, index)` (reverts OOB),
`accruedFees(token)`, `nextAgreementId()`, `protocolFeeBps()`, `feeRecipient()`,
`owner()`, `pendingOwner()`, `paused()`, `MAX_FEE_BPS()`, `BPS_DENOMINATOR()`,
`MAX_MILESTONES()`.

**No existence check:** an unknown `id` returns a zeroed `Agreement` (status numerically
`AwaitingFunding`) and an empty milestone array. Every state-changing path still rejects
it (`NotBuyer` for `fund`, `WrongState` for `approveMilestone`/`raiseDispute`,
`NotAuthorized` for `cancelBeforeFunding`), but integrators MUST track
`id < nextAgreementId()` and not treat zeroed structs as real agreements.

---

## 5. Token behaviour policy

| Token class | Behaviour | Policy |
|---|---|---|
| Standard ERC-20 | exact transfer | Supported. |
| ERC-20 returning `false` instead of reverting | broken | Rejected by `SafeERC20` (`SafeERC20FailedOperation`). Covered by tests with a mock. |
| ERC-20 returning no data (USDT-style) | non-standard but common | Supported by `SafeERC20`. Covered by tests. |
| **Fee-on-transfer / deflationary** | contract receives < `totalAmount` | **Rejected at `fund` with `UnsupportedTokenBehavior`.** The contract requires the balance delta to equal `totalAmount`, failing closed instead of silently under-collateralizing the agreement. |
| Rebasing / elastic supply | balance changes after funding | **Not supported.** Can break final payouts; documented, not defended. |
| Blocklist / pausable / freeze | transfers revert for some address | Not defendable at escrow layer; a frozen seller or contract balance blocks that milestone. |
| Malicious/reentrant token | calls back mid-transfer | `nonReentrant` on every fund-moving entry point; covered by a reentrant-token test. |
| Arbitrary decimals (0–18+) | value scaling | Supported: escrow stores raw units and never assumes 18 decimals. Frontend reads `decimals()`. |
| Non-contract `token` address | `safeTransferFrom` call to EOA | Fails closed on fund (call to non-contract reverts / returns empty → SafeERC20 failure). Cannot be funded. |

---

## 6. Threat catalogue (STRIDE-oriented)

### 6.1 Impersonation / spoofing

* **Buyer only** functions (`fund`, `approveMilestone`) check `msg.sender == buyer`
  directly; no signature schemes, no meta-transactions, no delegated calls.
* **Arbiter only** `resolveDispute` checks `msg.sender == arbiter`.
* Agreement identity is `msg.sender` at creation, so "buyer impersonation" requires
  stealing the buyer key or a contract-level delegatecall — out of scope for the core
  contract (account abstraction belongs to a future adapter layer, never to this
  settlement core).

### 6.2 Tampering

* Milestone array and amounts are immutable after `createAgreement`.
* `feeBps` is snapshotted per agreement; fee changes cannot rewrite history (invariant 7).
* Ownership is 2-step (`Ownable2Step`), so a typoed new owner cannot strand control.

### 6.3 Repudiation / disputes

* Every state change emits an event (`AgreementCreated`, `Funded`,
  `MilestoneReleased`, `DisputeRaised`, `DisputeResolved`, `AgreementCancelled`,
  `AgreementCompleted`, `FeesWithdrawn`, `ProtocolFeeUpdated`, `FeeRecipientUpdated`).
* Dispute evidence lives off-chain; the arbiter's on-chain decision is final and
  recorded by `DisputeResolved`. See `docs/ARBITRATION_MODEL.md`.

### 6.4 Information disclosure

* Everything is public chain data by design. No private fields, no encrypted inputs.
* Frontend must not leak private keys: only `NEXT_PUBLIC_*` variables, no wallet secrets.

### 6.5 Denial of service

| Vector | Impact | Status |
|---|---|---|
| Owner pause | all agreement liveness | Accepted admin power; can only be unpaused by owner. Documented. |
| Fee-on-transfer funding | under-collateralization | **Fixed:** fails closed at `fund`. |
| Buyer never approves / never disputes | milestone frozen | Requires the buyer's counterparty action (dispute by seller + arbiter). Seller can always dispute. |
| Arbiter never resolves | disputed milestone frozen | Accepted design risk (§3.4). |
| Seller rejects native payout | milestone cannot clear | Accepted; buyer chooses seller. |
| Fee recipient rejects native | native fees stuck | Owner can rotate recipient. |
| Gas-griefing via huge milestone count | bounded at 50; create loop O(n ≤ 50) | Bounded. |
| Full-history log scan by clients | RPC DoS / slow UI | Frontend hardened with bounded ranges (§ indexing docs). |

### 6.6 Elevation of privilege

* Owner cannot seize principal, resolve disputes, or mint anything.
* Arbiter cannot act on undisputed milestones or on other agreements.
* Fee recipient cannot withdraw more than `accruedFees`, and only fees.
* No `delegatecall`, no proxy, no selfdestruct, no upgrade hooks.

### 6.7 Reentrancy

* `fund`, `approveMilestone`, `resolveDispute`, `withdrawFees` are `nonReentrant`
  (single guard shared across all of them).
* External calls happen after state effects (CEI).
* Token callbacks and native `receive()` hooks are covered by tests
  (`ReentrantBuyer`, malicious-token mock).

### 6.8 Value conservation (the core guarantee)

For every agreement `a` and token `t`:

```
deposited(a) == released(a) + refunded(a) + accruedFees_from(a) + stillEscrowed(a)
```

and globally `balance(contract, t) >= sum(stillEscrowed) + accruedFees[t]` — with equality
for exact-supply tokens. Invariant-tested (see `contracts/test/NexusEscrow.Invariants.t.sol`).

---

## 7. Out-of-scope and explicit non-goals

* No on-chain arbitration logic, no evidence hashing, no appeal layer — the arbiter is a
  human/agent chosen out-of-band; see the arbitration model.
* No upgradeability, no bug-bounty escrow, no oracle dependence, no interest/yield.
* ERC-4337 / session keys / delegated authorization are **future adapter concerns**, not
  core settlement concerns. The core must stay deterministic.
* Chain reorg handling at the contract layer is not applicable (finality is the chain's
  job); reorg handling for **indexers and the frontend** is specified in
  `docs/INDEXING.md`.

---

## 8. Invariants (must hold at all times)

1. Escrow never pays more than deposited per (agreement, token).
2. `buyer + seller + protocol fees` conserve escrowed value for every milestone action.
3. A milestone cannot be released twice.
4. Completed milestone state cannot regress.
5. Unauthorized addresses cannot cause value transfer.
6. The protocol owner cannot directly seize escrow principal.
7. Fee changes cannot mutate historical agreements (`feeBps` snapshot).
8. Pause cannot corrupt an agreement (all paths are all-or-nothing; unpause restores).
9. Every terminal state leaves accounting internally consistent
   (`Completed`/`Cancelled` ⇒ no pending obligations for that agreement).
10. `nextMilestone` is monotonically non-decreasing and `<= milestoneCount`.
11. `accruedFees[t]` is fully backed by the contract's `t` balance at all times.
12. A release/resolve at index `i` is only possible when indices `< i` are terminal and
    index `i` is in the required state.

These are enforced by the stateful invariant suite in
`contracts/test/NexusEscrow.Invariants.t.sol` and the fuzz tests in
`contracts/test/NexusEscrow.Security.t.sol`.
