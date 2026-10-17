# Arbitration Model

> Contract: `contracts/src/NexusEscrow.sol`. Status: **unaudited / testnet.** This is a
> description of the implemented mechanism, not legal advice or a dispute policy.

## 1. Role

Each agreement names an **arbiter** at creation time (chosen by the buyer). The arbiter
is the only address that can resolve a disputed milestone. Arbitration happens **only**
after one of the two parties raises a dispute on the current milestone; the arbiter can
never act on its own initiative.

## 2. Powers

`resolveDispute(id, buyerBps)` with `0 <= buyerBps <= 10_000`:

- The disputed milestone amount is split:
  - `buyerAmount = floor(amount * buyerBps / 10_000)` — refunded to the buyer;
  - `sellerGross = amount - buyerAmount`;
  - `fee = floor(sellerGross * feeBps / 10_000)` — protocol fee, charged **only** on
    the seller side;
  - `sellerAmount = sellerGross - fee`.
- The milestone is marked `Resolved`; the cursor advances exactly one milestone; the
  agreement completes if that was the last milestone.
- `buyerBps = 10_000` refunds the buyer fully and charges no fee.
- `buyerBps = 0` awards the seller the full milestone minus the protocol fee.

## 3. Limits (what the arbiter cannot do)

- Act on an undisputed milestone (`WrongMilestoneState`).
- Act on any milestone other than the current `nextMilestone`.
- Act on any agreement where it is not the named arbiter (`NotArbiter`).
- Act when the agreement is not `Active` (paused, completed, cancelled all revert).
- Change amounts, fees, participants, or the fee recipient.
- Transfer more than the disputed milestone's amount, or drain principal from
  unrelated milestones.
- Bypass the pause guard, reentrancy guard, or any other invariant.

The worst case with a hostile arbiter is a maximal reallocation of the **current
disputed milestone** between buyer and seller, minus the seller-side fee. No path
exists to send escrow value to the arbiter itself.

## 4. Fee incidence

- The protocol fee is only ever computed on the portion of a milestone that is paid to
  the seller (release or arbitration). Buyer refunds are never taxed.
- The fee rate is snapshotted per agreement at creation (`feeBps`), so a later
  `setProtocolFee` cannot change the economics of an in-flight or disputed agreement.

## 5. Rounding

All splits round down (toward the buyer for refunds, toward the seller for the
remainder). The conservation equation holds exactly for every input:

```
buyerAmount + sellerAmount + fee == milestone.amount
```

Dust (sub-wei fractions of basis points) always lands on the seller side via the
remainder, never created or destroyed. This is fuzz-tested across the full
`buyerBps` x `feeBps` range and enforced by the invariant suite.

## 6. Selection and trust assumptions

| Assumption | Reality |
|---|---|
| Arbiter is independent | Enforced only as `arbiter != buyer && arbiter != seller` at creation. The contract cannot verify real-world independence. |
| Arbiter responds | **Not enforced.** There is no timeout or fallback. A silent arbiter freezes the disputed milestone indefinitely. |
| Arbiter is correct | Not enforceable on-chain. The decision is final; there is no appeal within this contract. |
| Arbiter is technically capable | The arbiter needs a wallet that can call `resolveDispute`; it can be a normal account, a multisig, or (in a future adapter) an automated settlement contract. |

The "no timeout by design" choice removes a class of timeout-griefing attacks, but it
creates a liveness dependency. Participants should treat arbiter selection as the most
important trust decision in the agreement. Recommended for real (future) usage: a
reputable professional, an established arbitration service, or a threshold multisig.
A future optional module may add a *buyer-refund-only* timeout for the disputed
milestone as a liveness backstop — it must never allow a seller-side release without
the buyer's consent.

## 7. Off-chain process (recommended, not enforced)

The contract stores no evidence and emits no reason. A workable process:

1. The party that believes the milestone is unmet raises `raiseDispute` (freezes the
   milestone; emits `DisputeRaised` with the milestone index and raiser).
2. Both parties submit evidence to the arbiter off-chain (the `DisputeRaised` event is
   a public timestamped anchor for when the dispute started).
3. The arbiter resolves with a basis-point split. `DisputeResolved` records the split
   and the fee permanently.
4. Unresolved later milestones proceed normally after resolution of the disputed one.

## 8. Explicit non-goals

- No on-chain evidence hashing or courts.
- No arbiter staking/slashing.
- No appeal window.
- No automated arbitration logic in the settlement core — the core stays deterministic
  and minimal. Automated agents can be arbiters as plain addresses; richer agent
  coordination belongs in adapter contracts outside this escrow.
