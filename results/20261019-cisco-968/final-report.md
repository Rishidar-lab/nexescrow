# NexEscrow × BOT Chain — Bohr 968 compatibility evidence

**Status:** Builder-side observational evidence only
**Network:** BOT Chain Bohr testnet
**Chain ID:** 968
**RPC:** https://rpc.bohr.life
**Repository commit before this evidence commit:** ba7223ae23032d64889b521c9ff68cc7e1d25f90

## Safety boundary

This run was read-only and bounded.

- No transaction was signed or broadcast.
- No contract was deployed.
- No induced reorganisation or stress test was attempted.
- BOT mainnet chain 677 was not accessed.
- No customer funds or production assets were involved.

## Probe results

All four harness stages completed:

- RPC capability probe: completed
- bounded `eth_getLogs` range probe: completed
- execution-trace capability probe: completed
- head/hash stability observation: completed

A completed probe means the observation process succeeded; it does not imply every optional RPC capability was available.

## Head/hash observation

The bounded Bohr observation recorded:

- 6 samples completed
- 78 unique block heights observed
- 0 block-hash replacements observed
- 0 parent-link breaks observed

This finite observation does not establish a BOT Chain finality or reorganisation guarantee.

## Execution tracing

Eight previously recorded NexEscrow Bohr lifecycle transactions were supplied to the execution-trace probe.

Observed:

- transactions supplied: 8
- transactions traced with `structLogs`: 0
- trace capability: not demonstrated by this run

The public Bohr endpoint returned JSON-RPC error `-32601`, indicating that
`debug_traceTransaction` does not exist or is not available on that endpoint.

Therefore this run cannot establish support or non-support for particular Cancun
opcodes or precompiles. It establishes only that the tested public RPC endpoint
did not expose the requested debug-tracing method.

## Remaining BOT-owner guidance

The builder-side evidence narrows the remaining questions to authoritative BOT
Chain guidance:

1. Recommended retry/backoff policy, if one is published or guaranteed.
2. Reorganisation/finality and recommended indexing safety depth for Bohr 968,
   beyond the previously supplied receipt-confirmation guidance.
3. Known Cancun opcode/precompile limitations, if any, relevant to the current
   Solidity 0.8.26 + `evmVersion="cancun"` deployment.

For item 3, BOT engineering can use the eight recorded transaction hashes from
`docs/evidence/bot-968/transactions.json` on an internal/debug-capable node if useful.

If no published recommendation or guarantee exists for an item, an explicit
statement to that effect is sufficient. NexEscrow will keep its application
policy clearly separated from BOT Chain guarantees.

## Evidence boundary

These results are not:

- a security audit;
- a production-readiness approval;
- a finality guarantee;
- a mainnet deployment approval;
- an ecosystem-support decision.
