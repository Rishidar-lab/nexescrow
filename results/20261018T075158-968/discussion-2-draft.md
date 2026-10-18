# Discussion #2 Draft — BOT Chain Network-Compatibility Harness Complete

**Status:** DRAFT — stored only, never posted
**Date:** 2026-10-18
**Commit:** `f6f76d2`

---

## Summary

The BOT Chain (Bohr testnet, chain-id 968) network-compatibility harness is now complete and has passed a bounded live run against `https://rpc.bohr.life`.

## What Was Built

- **`scripts/run-bot-network-compatibility.py`** — orchestrator that runs RPC capability, range-cap, head-stability, and optional execution-trace probes against a target chain. Supports chain 968 (default) and 677 (requires explicit `--allow-mainnet-read`).
- **`scripts/probe-bot-rpc.py`** — RPC capability probe testing 9 methods including `eth_chainId`, `eth_blockNumber`, `eth_getLogs` across multiple block ranges, with retry/backoff (5 attempts, 3/6/12/24s backoff, 3 repeats).
- **`scripts/probe-bot-rpc-range-cap.py`** — range-cap probe testing increasing block-range spans.
- **`scripts/observe-bot-head-stability.py`** — head-stability observer detecting block replacements and parent-link inconsistencies.
- **`scripts/probe-cancun-execution.py`** — Cancun-era opcode and precompile call analyzer (requires explicit `--transactions` file on chain 677).
- **`docs/BOT_NETWORK_COMPATIBILITY_HARNESS.md`** — full harness documentation including safety properties, responsibility boundary, dry-run instructions, and offline test coverage.

## Safety Properties

- Read-only by default; 677 requires explicit `--allow-mainnet-read` opt-in
- Credential-bearing RPC URLs rejected
- No deployment, broadcast, or transaction-sending capability
- Execution tracing on 677 requires explicit transaction evidence file from controlled exercise

## Offline Tests

- `tests/test_bot_network_compatibility.py` — 5 new harness-gate tests (span validation, range-cap enforcement, skip flags, execution-trace step, parse_span_list)
- `tests/test_bot_network_retry.py` — 5 retry/backoff tests (4 call_with_retry cases + 1 aggregation test)
- Full suite: EXIT=0

## Live Run Results (Run ID: `20261018T075158-968`)

- **Duration:** 66 seconds
- **Steps:** 1 passed (rpc-capability); range-cap and head-stability skipped
- **RPC requests:** 49 total, 0 errors, 0 HTTP 503s
- **Chain ID:** 968 confirmed
- **Latest block:** 27267261
- **Methods tested:** 9
- **eth_getLogs latency:** ~420ms median across all ranges (1 to 1001 blocks)
- **Artifacts:** 7 files in `results/20261018T075158-968/`

## Next Steps

- Full run with range-cap and head-stability enabled
- Execution-trace step with controlled 677 exercise transactions
- Integration into CI pipeline

---

*This draft is stored for reference only and has not been posted.*
