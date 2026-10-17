# BOT Chain JSON-RPC Capability Report

> Empirically measured 2026-10-08 (UTC) against the official endpoints:
> **BOT Bohr testnet** `https://rpc.bohr.life` (chain 968) and
> **BOT mainnet** `https://rpc.botchain.ai` (chain 677).
> Read-only: no transactions were signed or sent on either chain. `eth_call` and
> `eth_estimateGas` are node simulations.
>
> Raw data: `bot-rpc-capability.json` (merged matrix), `bot-rpc-flakiness.txt`
> (spaced repeatability probe).

## Verdict

**`eth_getLogs` is enabled and functional on both official RPC endpoints**, contrary
to the published statement that it is disabled. Both endpoints accept ranges from a
single block up to the entire chain history (empty-filter capability probe); there is
no observable hard range cap. The practical limits are **result volume and latency**,
not acceptance.

Observed caveats:

1. **Bohr is flaky at the gateway layer.** During the first probe (20:44–20:46 UTC) a
   run of requests returned nginx `503 Service Temporarily Unavailable` even for
   `eth_chainId` after a 60-second cooldown. The gateway recovered, and two later
   passes (85 and 67 requests) plus a 24-request spaced probe saw **zero** 503s. Treat
   5xx as transient and retry with backoff; do not treat a 503 as "method disabled".
2. **Payload/latency scale with range** for populated filters (mainnet: 64,000 blocks
   → 12,365 logs in ~4.0 s). Use bounded windows and checkpointing.
3. No `429` responses and no rate-limit headers were observed at conservative request
   rates (1 request/s; 5-request sequential burst).

## Method matrix

All tests: 3 repeats each, 1 request at a time, 25 s timeout, 1 s pause.
Values are median latency in ms. `count` is the decoded result size
(tx count for blocks, byte length for code/call data, gas for estimate, logs for logs).

| Method / case | Bohr 968 | Mainnet 677 | Notes |
|---|---|---|---|
| `eth_chainId` | ✅ 402 ms | ✅ 421 ms | 0x3c8 / 0x2a5, expected values |
| `eth_blockNumber` | ✅ 415 ms | ✅ 418 ms | |
| `eth_getBlockByNumber(latest,false)` | ✅ 441 ms (0 tx) | ✅ 413 ms (3 tx) | |
| `eth_getBlockByNumber(historical,false)` | ✅ 422 ms (2 tx) | ✅ 437 ms (2 tx) | |
| `eth_getCode(token)` | ✅ 407 ms (6,188 B) | ✅ 421 ms (2,410 B) | |
| `eth_call` empty → EOA | ✅ 411 ms (0 B) | ✅ 421 ms (0 B) | |
| `eth_call` `totalSupply()` → token | ✅ 422 ms (32 B) | ✅ 418 ms (32 B) | |
| `eth_estimateGas` 0-value transfer | ✅ 422 ms (24,338) | ✅ 410 ms (24,338) | simulation only |
| `eth_getTransactionReceipt(tx)` | ✅ 419 ms | ✅ 467 ms | real pre-existing txs |

No JSON-RPC errors, no retries, no 503 attempts in either final matrix run.

## eth_getLogs range ladder (address-filtered, populated)

### Bohr 968 — filter `0x75edC9335175Fc0552D51D48439F229c10420fe3` (test token)

| Range | Logs | Median | Max | Result |
|---|---|---|---|---|
| single latest block | 0 | 422 ms | 438 ms | ok |
| single historical block (26,170,440) | 1 | 423 ms | 458 ms | ok |
| 10 blocks | 0 | 440 ms | 459 ms | ok |
| 100 blocks | 0 | 408 ms | 418 ms | ok |
| 1,000 blocks | 0 | 428 ms | 457 ms | ok |
| 2,000 blocks | 0 | 410 ms | 429 ms | ok |
| 4,000 blocks | 0 | 448 ms | 454 ms | ok |
| 8,000 blocks | 23 | 458 ms | 520 ms | ok |
| 16,000 blocks | 25 | 415 ms | 540 ms | ok |
| 32,000 blocks | 50 | 539 ms | 554 ms | ok |
| 64,000 blocks | 112 | 693 ms | 881 ms | ok |
| 128,000 blocks | 172 | 777 ms | 780 ms | ok |
| 256,000 blocks | 282 | 965 ms | 980 ms | ok |
| 512,000 blocks | 451 | 1,004 ms | 1,045 ms | ok |
| 1,024,000 blocks | 852 | 1,181 ms | 1,261 ms | ok |
| 2,048,000 blocks | 2,214 | 1,384 ms | 1,490 ms | **max reliable** (1.4 s) |
| 4,096,000 blocks | 7,643 | 10,585 ms | 21,705 ms | accepted but too slow; stopped |

### Mainnet 677 — filter `0x68CAeA9104419203cF8b8f0B222E75709B97bfc6` (Wrapped BOT)

| Range | Logs | Median | Max | Result |
|---|---|---|---|---|
| single latest block | 1 | 430 ms | 467 ms | ok |
| single historical block (26,011,341) | 1 | 423 ms | 542 ms | ok |
| 10 blocks | 1 | 414 ms | 419 ms | ok |
| 100 blocks | 5 | 453 ms | 468 ms | ok |
| 1,000 blocks | 99 | 660 ms | 662 ms | ok |
| 2,000 blocks | 262 | 967 ms | 1,108 ms | ok |
| 4,000 blocks | 573 | 1,330 ms | 1,341 ms | ok |
| 8,000 blocks | 1,174 | 1,253 ms | 1,709 ms | ok |
| 16,000 blocks | 2,422 | 1,321 ms | 1,620 ms | ok |
| 32,000 blocks | 5,371 | 2,047 ms | 2,431 ms | ok |
| 64,000 blocks | 12,365 | 4,022 ms | 4,165 ms | accepted; stopped by 10k-log payload policy |

## Range-cap probe (empty-result filter)

To isolate acceptance from payload, `eth_getLogs` was queried with a zero-address
filter returning no logs, one request per span, with 5xx retries.

| Span | Bohr 968 | Mainnet 677 |
|---|---|---|
| 128,000 blocks | — | ✅ 528 ms |
| 512,000 blocks | — | ✅ 457 ms |
| 2,000,000 blocks | — | ✅ 436 ms |
| 8,000,000 blocks | ✅ 489 ms | ✅ 522 ms |
| 16,000,000 blocks | ✅ 570 ms | — |
| 32,000,000 blocks (≈ full history) | ✅ 3,051 ms | ✅ 598 ms |
| **Hard range cap** | **none observed** | **none observed** |

## Max reliable block range

- **Bohr 968:** 2,048,000 blocks (~1.4 s median with a populated filter). 4,096,000
  blocks was accepted but averaged 10.6 s and peaked at 21.7 s — not reliable.
- **Mainnet 677:** no capability failure observed; the tested ladder stopped at 64,000
  blocks because the filter alone returned 12,365 logs (~4.0 s). Capability probe shows
  full-history empty-filter scans in ~0.6 s.
- **No explicit server-side cap** was discovered on either endpoint. Reliability is
  governed by result volume, which scales with (range × contract activity).

## Rate limiting and availability observations

- No HTTP 429, no `Retry-After`, no `X-RateLimit-*` headers on either endpoint.
- Sequential bursts of 5 light calls: 5/5 OK on both chains (~0.4 s each).
- Spaced probe (12 calls × 1 s apart) on each chain: 24/24 OK (`bot-rpc-flakiness.txt`).
- **Transient 503 incident:** 2026-10-08 20:44–20:46 UTC, Bohr returned nginx
  `503 Service Temporarily Unavailable` (HTML body) for `eth_getLogs` and subsequent
  `eth_getCode`/`eth_call`/receipt calls, and a single `eth_chainId` after a 60 s
  cooldown. Recovery was observed within ~2 minutes. Note: the raw JSON of that first
  failed run was overwritten by the subsequent successful run; the failure mode is
  reported here from the session output, and the retry logic added to the probe was
  not exercised in the final matrices.
- Interpretation: 503s look like upstream capacity/rolling-restart behaviour rather
  than per-client rate limiting. Production consumers must retry with backoff.

## Pinned test targets

| Item | Bohr 968 | Mainnet 677 |
|---|---|---|
| Log filter address | `0x75edC9335175Fc0552D51D48439F229c10420fe3` (test "Tether USD") | `0x68CAeA9104419203cF8b8f0B222E75709B97bfc6` (Wrapped BOT) |
| Historical block | 26,170,440 | 26,011,341 |
| Receipt tx | `0xbfe1c6eedd53e4ee240bb60ca9bfccebe6b8e0953ba8630b8ddd97706c0a963c` | `0x278900611948392f57c7a0525f69b9ed5832f41d77a5a910bd2b727edc191c0e` |

Addresses and transactions were located via the respective Blockscout APIs
(`/api/v2/token-transfers`), then verified over JSON-RPC.

## Reproduction

```shell
python3 scripts/probe-bot-rpc.py \
  --name bot-bohr-testnet --rpc-url https://rpc.bohr.life --expected-chain-id 968 \
  --log-address 0x75edC9335175Fc0552D51D48439F229c10420fe3 \
  --historical-block 26170440 \
  --receipt-tx 0xbfe1c6eedd53e4ee240bb60ca9bfccebe6b8e0953ba8630b8ddd97706c0a963c \
  --max-range 34000000 --out /tmp/bohr.json

python3 scripts/probe-bot-rpc.py \
  --name bot-mainnet --rpc-url https://rpc.botchain.ai --expected-chain-id 677 \
  --log-address 0x68CAeA9104419203cF8b8f0B222E75709B97bfc6 \
  --historical-block 26011341 \
  --receipt-tx 0x278900611948392f57c7a0525f69b9ed5832f41d77a5a910bd2b727edc191c0e \
  --out /tmp/mainnet.json

python3 scripts/probe-bot-rpc-range-cap.py \
  --name bot-mainnet --rpc-url https://rpc.botchain.ai \
  --spans 128000,512000,2000000,8000000,32000000 --out /tmp/mainnet-cap.json
```

## Indexing decision (Task 2)

**Classification: B — bounded-block-window polling required** (in practice), with the
finding that classification A is *technically* viable today.

Rationale:

- Native `eth_getLogs` **works** on both official endpoints; an external indexer (C) is
  not required for functional agreement discovery, and no hybrid split (D) is needed
  yet. The current `AgreementIndexAdapter` boundary already permits adding one later.
- However, reliability is governed by payload and latency, not acceptance. For the
  escrow contract's own low-volume logs a full-history scan is technically feasible,
  but unbounded scans: (a) get slower as activity grows (mainnet 64k blocks -> 12.4k
  logs -> 4 s for a *token*, before any escrow deployment exists), (b) make checkpoint
  progress and reorg reconciliation coarse, and (c) depend on a method the operator's
  own documentation currently describes as disabled.
- Therefore keep/use bounded windows with a confirmed-block checkpoint — exactly the
  strategy already implemented in `frontend/src/lib/indexer/logScan.ts`
  (2,000-block chunks, dedupe by `(chainId, contractAddress, txHash, logIndex)`,
  `latest - confirmations` head, rescan-based reorg handling). No redesign is needed;
  the measured evidence supports the existing design.
- If `eth_getLogs` is later disabled as documented, the HTTP indexer adapter
  (`docs/INDEXING.md` §4) is the fallback; the UI already prefers it when
  `NEXT_PUBLIC_INDEXER_URL` is set.
