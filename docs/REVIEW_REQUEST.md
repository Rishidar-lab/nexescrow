# NexEscrow PR #1 — review request (corrected draft)

**Repository:** `Rishidar-lab/nexescrow`
**PR:** https://github.com/Rishidar-lab/nexescrow/pull/1 — *feat: add BOT Chain integration and Bohr 968 validation*
**Head branch:** `feat/botchain-integration`
**Head SHA:** `24cc8c81588cb08bdc350ca361120f025c0a9544`
**Base branch:** `master` (`7183779347048ebcc443dc00b1d1df40cc147277`)
**State:** OPEN · draft=true · not merged · no mainnet deployment

## Review scope

Review PR #1 only, against head `24cc8c8` on base `master`. The contract under review is `contracts/src/NexusEscrow.sol` (milestone-based escrow: `createAgreement`, `fund`, `approveMilestone`, `raiseDispute`, `resolveDispute`, `cancelBeforeFunding`, `withdrawFees`). Frontend and script changes in the same PR are out of scope for this technical review unless cited as evidence.

**Dependency context:** PR #1 branches directly from `master`; it has no dependency on the Demo-1 tranche stack (`whitepaper/demo-1-hardening` → `feat/demo1-tranche-a-core-20261012` → … → `feat/demo1-tranche-f-indexer-20261012`). Demo-1 (`contracts/src/NexEscrowCore.sol`, `ResolutionPolicy`, `_validatePolicy`) is a separate, unmerged stack and is **not** part of PR #1. Nothing in this review request references Demo-1 symbols.

## Symbol audit — what was removed and why

Earlier review drafts named three locations. Each was checked against `24cc8c8` (and every other local branch). Two do not exist in NexEscrow and are removed; one exists and is retained.

| Named symbol (earlier draft) | Status at `24cc8c8` | Disposition |
|---|---|---|
| `ScopeValidator._pattern_matches` | **Not found** anywhere in NexEscrow | Removed — this symbol belongs to Morphia (`~/morphia-work/Morphia-alpha-stack/apps/api/`), not NexEscrow |
| `verify_finding` | **Not found** anywhere in NexEscrow | Removed — this symbol belongs to Morphia, not NexEscrow |
| `_payOut` | **Found** — `contracts/src/NexusEscrow.sol:413` | Retained, question below |

Verification: `git grep -rn "ScopeValidator\|verify_finding"` over all local branches returned zero hits. `_payOut` is defined at line 413 and called at lines 285, 332, 333, 364 of the same file.

## Verified question (NexEscrow, PR #1)

**Q1 — Native-transfer failure handling in `_payOut`**

File: `contracts/src/NexusEscrow.sol`, line 413, head `24cc8c8`.

```solidity
function _payOut(address token, address to, uint256 amount) internal {
    if (amount == 0) return;
    if (token == address(0)) {
        (bool ok,) = payable(to).call{ value: amount }("");
        if (!ok) revert NativeTransferFailed();
    } else {
        IERC20(token).safeTransfer(to, amount);
    }
}
```

`_payOut` is invoked for the seller payout on milestone approval (`approveMilestone`, line 285), buyer/seller split on dispute resolution (`resolveDispute`, lines 332–333), and fee withdrawal (`withdrawFees`, line 364). For native asset (`token == address(0)`), failure reverts `NativeTransferFailed()`.

**Bounded question:** When a seller address is a non-payable contract or otherwise rejects the native transfer, `approveMilestone` reverts `NativeTransferFailed()` after the milestone has already been marked `Released` and `_advance` has run. Is that the intended failure semantics — i.e., does the milestone stay released with funds unpaid, or should the payout failure roll back the milestone release? What does a seller "rejecting value" mean operationally, and is there a recovery path for the buyer?

**Evidence:** call sites at `contracts/src/NexusEscrow.sol:285,332,333,364`; error `NativeTransferFailed()` declared in the same file; `approveMilestone` marks `m.status = MilestoneStatus.Released` before `_payOut`.

**Limitation:** This is code review of a testnet contract (`auditStatus: UNAUDITED`). It does not establish production readiness, re-entrancy safety beyond `nonReentrant`, or mainnet behavior. The mainnet deployment guard (`DeployPolicy`, `ALLOW_MAINNET_DEPLOYMENT`) is unchanged by PR #1 and is not part of this review.

## Outstanding BOT network questions (kept separate)

These concern BOT network operation, not the PR #1 contract code. Application observations (local dry runs, read-only `eth_getCode`/`eth_getLogs` against Bohr 968 testnet) are **not** presented as authoritative network policy.

1. **RPC / log-query and retry guidance.** The frontend polls a bounded block window. What is BOT's recommended query pattern, block-range size, and retry/backoff behaviour for log queries? This cannot be settled by local measurement alone.
2. **Finality / indexing policy.** Current policy (2 write-receipt confirmations, 12-block indexing safety depth) is deliberately provisional. What are BOT's finality recommendations and the safe indexing depth for escrow state?
3. **Cancun compatibility.** Does BOT Bohr 968 testnet (and mainnet) support the Cancun hard fork features the contract/frontend assume?

## What this review would establish

If answered, this review establishes:
- Whether `_payOut`'s native-transfer failure semantics match the intended milestone-release contract (Q1), with a precise file:line anchor at `contracts/src/NexusEscrow.sol:413` on head `24cc8c8`.
- That the two Morphia-sourced review points (`ScopeValidator._pattern_matches`, `verify_finding`) have no target in NexEscrow and should not be raised against PR #1.

It does **not** establish mainnet safety, independent audit status, or any network-policy position. The three BOT questions remain network-provider matters.

## What this is not

- Not an email to Leon or anyone else.
- Not a claim of independent review; all findings are reproducible local code inspection.
- Not a change to mainnet guards or any deployment configuration.
- Not a merge or retarget of PR #1 or any PR in the stack.
