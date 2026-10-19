## Bohr 968 compatibility evidence — bounded read-only follow-up

Following Leon's guidance, I completed the bounded builder-side compatibility
run against BOT Chain Bohr testnet (chain 968).

### Safety boundary

- read-only
- Bohr 968 only
- no transaction signing or broadcast
- no deployment
- no stress testing
- no induced reorganisation
- no BOT mainnet 677 access
- no customer funds

### Results

All four harness stages completed:

- RPC capability probe
- bounded `eth_getLogs` range probe
- execution-trace capability probe
- block/hash head-stability observation

The bounded head observation completed 6 samples covering 78 unique block
heights.

Observed during that finite window:

- 0 block-hash replacements
- 0 parent-link breaks

This is observational evidence only and is not presented as a finality or
reorganisation guarantee.

### Execution-trace capability

Eight previously recorded NexEscrow Bohr lifecycle transactions were supplied
to the execution-trace probe.

The public Bohr endpoint returned JSON-RPC error `-32601`:

`debug_traceTransaction` does not exist or is not available.

Accordingly:

- 8 lifecycle transactions were supplied;
- 0 produced `structLogs`;
- debug-trace capability was not demonstrated by this public endpoint.

This does not establish lack of Cancun opcode or precompile support at the BOT
protocol/node level. It only establishes that the tested public endpoint did not
expose the requested debug-tracing method.

If useful, BOT engineering can use the same eight transaction hashes in
`docs/evidence/bot-968/transactions.json` against an internal/debug-capable node.

### Remaining network-owner guidance

The remaining questions are now limited to authoritative BOT guidance:

1. Recommended retry/backoff policy, if one is published or guaranteed.
2. Reorganisation/finality or recommended indexing safety depth for Bohr 968,
   beyond the previously supplied receipt-confirmation guidance.
3. Known Cancun opcode/precompile limitations, if any, relevant to Solidity
   0.8.26 with `evmVersion="cancun"`.

If BOT does not publish or guarantee one of these items, an explicit statement
to that effect is sufficient. NexEscrow will keep its own conservative
application policy clearly separated from BOT Chain guarantees.

Full machine-readable evidence is retained with the run bundle.

This evidence is not a security audit, production-readiness approval, finality
guarantee, mainnet deployment approval, or ecosystem-support decision.
