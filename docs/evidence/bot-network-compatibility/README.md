# BOT Bohr 968 — read-only network-compatibility observation

Produced by `scripts/run-bot-network-compatibility.py` (default chain 968). The
run is read-only: no transaction, deployment, or mainnet (677) access. See
`docs/BOT_NETWORK_COMPATIBILITY_HARNESS.md` for the harness design.

- Run (UTC): `2026-10-17T15:26:00Z` → `2026-10-17T15:29:59Z`
- Network: `bot-bohr-testnet` (chain **968**), RPC `https://rpc.bohr.life`
- Flags: `read_only=true`, `mainnet_read_opt_in=false`, `dry_run=false`
- Steps: `rpc-capability` ✓, `eth-getLogs-range-cap` ✓, `head-stability` ✓ (all exit 0)

## OBSERVED (empirical, this bounded run only)

- **Chain identity:** `observed_chain_id == 968`, matching the expected id.
- **`eth_getLogs` range cap:** with an empty-result address filter (isolates range
  handling from payload size), spans of 500 / 1000 / 2000 blocks ending at
  `latest_block 27188497` each returned HTTP 200 (`ok`) at 500.5 / 533.8 / 567.0 ms.
  The 2,000-block window NexEscrow enforces was serviceable on this endpoint
  during the run.
- **Head stability:** 6 samples; 78 unique heights seen; **0** block-hash
  replacements and **0** parent-link breaks observed across the window.

## NOT established by this run

These are observations, **not** BOT Chain guarantees. In particular, zero
observed hash replacements over a ~2-minute window does **not** establish a
finality or reorganisation guarantee. The three network-owner questions for
Cisco/BOT remain open:

1. Recommended retry/backoff policy.
2. Reorg / finality / indexing-depth guidance beyond 2 receipt confirmations,
   separately for chains 968 and 677.
3. Cancun opcode/precompile limitations for Solidity 0.8.26 + `evmVersion="cancun"`.

NexEscrow's 12-block indexing safety depth and 3-attempt transient-read retry
remain **application policies**, not BOT guarantees.

## Reproduce

```
python3 scripts/run-bot-network-compatibility.py --dry-run   # inspect the plan
python3 scripts/run-bot-network-compatibility.py             # read-only 968 run
```

## Artifact digests (sha256, from manifest.json)

| file | sha256 | bytes |
|------|--------|-------|
| bot-bohr-testnet-rpc-capability.json | `447b1d81c40ee6687b09208190b90ae2a346913da6a284fc2e3849e57d55392a` | 25981 |
| bot-bohr-testnet-range-cap.json | `3ed0037bd236da6c7f8d000130f1431bc8f9bba4394730a38e79bc0b971c5366` | 1182 |
| bot-bohr-testnet-head-stability.json | `06c679bfe000f0f7a4ee226f01dcedb2ffbe68e9f33ee8ac01236b91d67d5415` | 26922 |
