# BOT Chain Network-Compatibility Harness — Final Report

**Date:** 2026-10-18
**Commits:** `f6f76d2` (C1), `1b61018` (C2)
**Run ID:** `20261018T075158-968`

---

## 18-Point Summary

### Scripts & Probes

1. **Orchestrator** (`scripts/run-bot-network-compatibility.py`) — runs RPC capability, range-cap, head-stability, and optional execution-trace probes; supports chain 968 (default) and 677 (requires `--allow-mainnet-read`).

2. **RPC capability probe** (`scripts/probe-bot-rpc.py`) — tests 9 RPC methods including `eth_chainId`, `eth_blockNumber`, `eth_getLogs` across multiple block ranges; 546 lines.

3. **Range-cap probe** (`scripts/probe-bot-rpc-range-cap.py`) — tests increasing block-range spans to detect RPC range limits.

4. **Head-stability observer** (`scripts/observe-bot-head-stability.py`) — detects block replacements (same height, different hash) and parent-link inconsistencies.

5. **Cancun execution analyzer** (`scripts/probe-cancun-execution.py`) — reports Cancun-era opcodes (`BLOBHASH`, `BLOBBASEFEE`, `TLOAD`, `TSTORE`, `MCOPY`) and standard precompile calls (`0x01`–`0x0a`) from execution traces.

### Safety & Gates

6. **Retry/backoff** — 5 attempts max, fixed 3/6/12/24s backoff, 3 repeats per probe; RETRYABLE_HTTP = {429, 502, 503, 504}.

7. **Read-only default** — 677 requires explicit `--allow-mainnet-read`; credential-bearing RPC URLs rejected.

8. **Trace gate** — 677 `--include-execution-trace` requires explicit `--transactions` file (ValueError otherwise); 968 default `docs/evidence/bot-968/transactions.json`.

9. **Span validation** — `parse_span_list` rejects non-integer, zero, negative, or >2000 values; requires at least one span.

10. **Max-range gate** — `--max-range` capped at 2000 blocks; error message `--max-range {value} exceeds the 2000-block limit`.

11. **Skip flags** — `--skip-range-cap` and `--skip-head-stability` are plain `store_true` flags; skipped steps appear neither in printed plan nor generated bundle.

### Tests

12. **Harness-gate tests** (`tests/test_bot_network_compatibility.py`) — 5 new methods: `test_execution_trace_step_is_added_on_968`, `test_parse_span_list_accepts_ordered_values`, `test_range_cap_rejects_values_above_limit`, `test_skip_flags_remove_optional_steps`, `test_span_validation_errors`.

13. **Retry tests** (`tests/test_bot_network_retry.py`) — 5 tests: 4 `TestCallWithRetry` cases + 1 `TestMeasure.test_aggregates_repeated_calls`.

14. **Smoke validation** — 6/6 green (exits 0/2/2/2/2/2); errors verified: 677 gate, max-range, spans validation, empty spans.

15. **Full test suite** — `python3 -m unittest discover -s tests` → EXIT=0.

### Documentation

16. **Harness doc** (`docs/BOT_NETWORK_COMPATIBILITY_HARNESS.md`) — 4 edits applied: retry/backoff para, skip-flags para, trace gate semantics, offline test coverage bullets; 154 lines.

### Live Run

17. **Bounded live run** (run ID `20261018T075158-968`) — 66 seconds, 1 step passed (rpc-capability), 49 requests, 0 errors, 0 HTTP 503s; chain ID 968 confirmed; latest block 27267261; 9 methods tested; ~420ms median latency.

18. **Evidence artifacts** — 7 files in `results/20261018T075158-968/`: `bot-bohr-testnet-rpc-capability.json` (24267 bytes, sha256 `42a99023...`), `manifest.json`, `metadata.json`, `observations.jsonl`, `requests.jsonl`, `responses.jsonl`, `summary.json`.

---

## Verification Commands

```bash
# Full test suite
python3 -m unittest discover -s tests -v

# Smoke validation
python3 scripts/run-bot-network-compatibility.py --dry-run --out-dir /tmp/smoke-test 2>&1

# Live bounded run
python3 scripts/run-bot-network-compatibility.py \
  --chain-id 968 --rpc-url https://rpc.bohr.life \
  --max-range 100 --spans 50 --samples 1 \
  --skip-range-cap --skip-head-stability \
  --out-dir results/$(date -u +%Y%m%dT%H%M%S)-968
```

## Notes

- No push, no PR merge, no history rewrite performed.
- Discussion #2 draft stored in `results/20261018T075158-968/discussion-2-draft.md` (never posted).
- All work on branch `feat/botchain-integration`.
