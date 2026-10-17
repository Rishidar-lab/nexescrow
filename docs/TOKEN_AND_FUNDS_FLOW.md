# Token & Funds Flow

> Contract: `contracts/src/NexusEscrow.sol`. All value is accounted in raw token units
> (wei for the native asset). The contract never assumes 18 decimals.

## 1. Assets

| Asset | Representation | Transfer mechanism |
|---|---|---|
| Native asset (BOT on BOT Chain, NEX on Nexus, ETH on local anvil, …) | `token == address(0)` | `msg.value` in, `call{value:}` out |
| ERC-20 | token contract address | `SafeERC20.safeTransferFrom` in, `safeTransfer` out |

There is no wrapping, bridging, yield, or rehypothecation. Funds sit idle in the
contract until a milestone action moves them.

## 2. Funding

`fund(id)`, buyer only, agreement must be `AwaitingFunding`:

- **Native:** `msg.value` must equal `totalAmount` exactly (`NativeValueMismatch`
  otherwise). No partial funding, no overpayment.
- **ERC-20:** `msg.value` must be 0; the contract measures its own balance before and
  after `safeTransferFrom` and requires the delta to equal `totalAmount` **exactly**.
  If the token under-delivers (fee-on-transfer/deflationary), the call reverts with
  `UnsupportedTokenBehavior`: the agreement stays unfunded rather than becoming
  silently under-collateralized.

After funding, `status = Active` and the full `totalAmount` is held by the contract.

## 3. Release

`approveMilestone(id)`, buyer only, current milestone must be `Pending`:

```
fee          = floor(amount * feeBps / 10_000)
sellerAmount = amount - fee
```

- `sellerAmount` is paid to the seller; `fee` is added to `accruedFees[token]`.
- The milestone is marked `Released`, the cursor advances, and the agreement completes
  if it was the last milestone.

`resolveDispute(id, buyerBps)`, arbiter only, current milestone must be `Disputed`:

```
buyerAmount  = floor(amount * buyerBps / 10_000)      // refund, untaxed
sellerGross  = amount - buyerAmount
fee          = floor(sellerGross * feeBps / 10_000)
sellerAmount = sellerGross - fee
```

- Buyer refund and seller payout are skipped when zero (no zero-value native calls).
- Milestone → `Resolved`, cursor advances, agreement completes on the last milestone.

## 4. Fee withdrawal

`withdrawFees(token)`, callable only by the current `feeRecipient`:

- Sends exactly `accruedFees[token]` and zeroes it. It cannot touch escrowed principal
  (`NothingToWithdraw` when nothing has accrued).
- Not blocked by pause: fees must not be hostage to an availability incident.
- Changing `feeRecipient` rotates the claim: fees accrued under a previous recipient
  are withdrawable by the new recipient. This is intended (the claim belongs to the
  protocol) and disclosed.

## 5. Conservation

For every agreement `a` and token `t`:

```
deposited(a) == released(a) + refunded(a) + fees_from(a) + still_escrowed(a)
```

Globally, with exact-supply tokens:

```
balance(contract, t) == Σ still_escrowed_over_active_agreements + accruedFees[t]
```

Both are asserted by the stateful invariant suite
(`contracts/test/NexusEscrow.Invariants.t.sol`) over randomized
create/fund/approve/dispute/resolve/cancel/admin/pause/warp sequences, and by fuzz
tests over fee and split rounding.

## 6. Token support matrix

| Behaviour | Support | Notes |
|---|---|---|
| Standard ERC-20 (returns `true`) | ✅ | |
| No-return (USDT-style) | ✅ | `SafeERC20` treats empty returndata as success; tested |
| Returns `false` instead of reverting | ❌ fails closed | `SafeERC20FailedOperation`; tested |
| Fee-on-transfer / deflationary | ❌ rejected at `fund` | `UnsupportedTokenBehavior`; tested |
| Rebasing / elastic supply | ❌ unsupported | Balance changes after funding can break later payouts; documented, not defended |
| Pausable / blocklist / freeze | ⚠️ not defended | A token that freezes the contract or a counterparty can block that milestone |
| Malicious/reentrant token | ✅ guarded | `nonReentrant` on all fund-moving paths; tested with a reentrant ERC-20 during fund and payout |
| Arbitrary decimals (0–18+) | ✅ | Raw units only; frontend reads `decimals()`; tested at 0/6/8/18 |
| Non-contract token address | ❌ fails closed | Call to an EOA reverts on the `balanceOf` return decode; cannot be funded |
| Native asset | ✅ | Exact value in/out; reverting payees revert the whole call (see below) |

## 7. Edge cases

- **Reverting native receiver.** If the seller (or a refunded buyer) is a contract that
  rejects native value, that payout reverts the whole transaction. The milestone stays
  untouched and funds remain escrowed. Arbitration can route around a rejecting seller
  with `buyerBps = 10_000` (buyer refund touches only the buyer).
- **Dust.** Sub-basis-point remainders go to the seller via the subtraction remainder;
  nothing is minted or burned by rounding.
- **Unknown ids.** Reads on unknown ids return zeroed structs; every state-changing
  path rejects them, but integrators must bound ids by `nextAgreementId()`.
- **Fee-recipient contract that rejects native.** Native fees are stuck until the owner
  points `feeRecipient` at a payable address; ERC-20 fees are unaffected.
