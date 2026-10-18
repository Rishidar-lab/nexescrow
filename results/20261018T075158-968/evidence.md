# Live Run Evidence — BOT Chain 968 Bounded Compatibility Run

**Run ID:** `20261018T075158-968`
**Date (UTC):** 2026-10-18
**Network:** bot-bohr-testnet (chain 968)
**RPC:** `https://rpc.bohr.life`
**Commit:** `f6f76d2` (test(harness): add BOT network-compatibility harness with retry, trace gate, and span validation)

---

## Run Command

```bash
python3 scripts/run-bot-network-compatibility.py \
  --chain-id 968 \
  --rpc-url https://rpc.bohr.life \
  --max-range 100 \
  --spans 50 \
  --samples 1 \
  --skip-range-cap \
  --skip-head-stability \
  --out-dir results/20261018T075158-968
```

**Started:** 2026-10-18T07:51:58Z
**Completed:** 2026-10-18T07:53:04Z
**Duration:** 66 seconds

---

## Parameters

| Parameter | Value |
|-----------|-------|
| chain_id | 968 |
| max_range | 100 |
| max_results | 10000 |
| range_spans | 50 |
| head_samples | 1 (skipped) |
| head_interval_s | 5.0 (skipped) |
| head_depth | 12 (skipped) |
| dry_run | false |

---

## Steps

### 1. rpc-capability — PASSED (exit 0)

**Command:**
```
/usr/bin/python3 scripts/probe-bot-rpc.py \
  --name bot-bohr-testnet \
  --rpc-url https://rpc.bohr.life \
  --expected-chain-id 968 \
  --max-range 100 \
  --max-results 10000 \
  --out results/20261018T075158-968/bot-bohr-testnet-rpc-capability.json \
  --log-address 0x6448668ae9cbbc41617c2bd5e4f29279320a2700 \
  --historical-block 26178651 \
  --receipt-tx 0x4216d1e1eb33e296e3a3040baa723b507ce2da449d60e6ffe9456cecacf6da61
```

**Results:**
- observed_chain_id: 968 ✅
- latest_block: 27267261
- methods_tested: 9
- total_requests: 49
- http_503_attempts: 0
- range_stop_reason: null (no stop triggered)

**eth_getLogs ranges tested:**

| Label | Span | all_ok | median_ms | count |
|-------|------|--------|-----------|-------|
| single latest block | 1 | true | 420.7 | 0 |
| single historical block | 1 | true | 420.4 | 1 |
| 10-block range | 11 | true | 430.6 | 0 |
| 100-block range | 101 | true | 413.0 | 0 |
| 1000-block range | 1001 | true | 420.8 | 0 |

**Stderr:** empty

---

## Artifacts

| File | SHA-256 | Bytes |
|------|---------|-------|
| `bot-bohr-testnet-rpc-capability.json` | `42a99023db7f19f351030f6de485ab8f9d607a380da2bc4c0cac273aad20d464` | 24267 |
| `manifest.json` | — | 3167 |
| `metadata.json` | — | 555 |
| `observations.jsonl` | — | 7559 |
| `requests.jsonl` | — | 7559 |
| `responses.jsonl` | — | 5844 |
| `summary.json` | — | 611 |

---

## Evidence Boundary

This run is **observational only**:
- No transactions sent
- No deployment performed
- Does not establish: finality guarantee, retry/backoff policy, opcode/precompile guarantee, security audit, production readiness, or ecosystem-support approval

---

## Analyst Notes

- All 49 RPC requests succeeded with 0 HTTP 503 errors.
- Median latency ~420ms across all eth_getLogs ranges (1 to 1001 blocks).
- Chain ID 968 confirmed. Latest block 27267261.
- Range-cap and head-stability steps were skipped to keep run bounded (~4 min target; actual 66s).
- No execution-trace step (requires explicit `--transactions` file from controlled exercise).
