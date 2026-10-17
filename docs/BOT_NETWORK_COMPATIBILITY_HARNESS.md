# BOT Network Compatibility Harness

Status: **builder-side tooling; no new live measurements are claimed by this document.**

This harness packages the read-only evidence offered to BOT Chain's node/backend
review. It is designed to reduce investigation work without crossing the
responsibility boundary between NexEscrow and BOT Chain.

## Responsibility boundary

NexEscrow can provide reproducible observations:

- bounded `eth_getLogs` behaviour and request parameters;
- observed RPC failures/retries and response timing;
- recent block/hash stability observations;
- checkpoint/rebuild evidence from the application-side indexer;
- execution-trace inventory when the RPC exposes `debug_traceTransaction`.

BOT Chain remains the authority for:

- recommended retry/backoff policy;
- protocol/operator finality or reorganisation guarantees;
- recommended indexing safety depth for 968 and 677;
- authoritative Cancun opcode/precompile support or limitations.

A successful probe is **not** a security audit, production-readiness approval,
ecosystem-support decision, or finality guarantee.

## Safety properties

The orchestrator and probes are read-only. They do not call transaction-send
methods and do not accept private keys or mnemonics.

Chain 968 is the default. Chain 677 is rejected unless the operator explicitly
passes `--allow-mainnet-read`. That flag permits RPC observation only; it does
not enable a deployment, transaction, customer funds, or any other write.

RPC URLs containing credentials, query parameters, or fragments are rejected
because the evidence bundle records the URL.

## Bohr 968 dry run

```bash
python3 scripts/run-bot-network-compatibility.py --dry-run
```

This prints the exact planned subprocesses and evidence boundaries without
making a network request.

## Bohr 968 observation bundle

```bash
python3 scripts/run-bot-network-compatibility.py
```

By default the bundle uses the recorded Demo 0 Bohr deployment as the pinned
address/history target and writes generated observations beneath:

`docs/evidence/bot-network-compatibility/`

The bundle includes:

1. RPC capability and bounded log-query observations using
   `scripts/probe-bot-rpc.py`;
2. a 500/1000/2000-block empty-result range check using
   `scripts/probe-bot-rpc-range-cap.py`;
3. repeated recent-block hash observations using
   `scripts/observe-bot-head-stability.py`;
4. a manifest with SHA-256 hashes for generated evidence files.

The default maximum range is deliberately 2,000 blocks to match the network
guidance already received. Larger experimental ranges should be run only when
there is a specific review reason and should be documented as experiments, not
supported limits.

## Recorded execution-path inventory

If the RPC exposes `debug_traceTransaction`, the recorded Bohr lifecycle can be
used to inventory opcodes that were actually executed and calls observed to the
standard precompile address range:

```bash
python3 scripts/run-bot-network-compatibility.py \
  --include-execution-trace
```

This adds `probe-cancun-execution.py` to the bundle. It reports the Cancun-era
opcodes `BLOBHASH`, `BLOBBASEFEE`, `TLOAD`, `TSTORE`, and `MCOPY` only when they
appear in returned execution traces. It also records observed calls to standard
precompile addresses `0x01` through `0x0a`.

If `debug_traceTransaction` is unavailable, the report records that limitation.
It must not infer support or non-support for opcodes/precompiles from the absence
of a trace endpoint.

## Head/reorg observations

`observe-bot-head-stability.py` repeatedly reads the current head and the recent
block window. If the same height is later returned with a different hash, that
replacement is recorded. Parent-link inconsistencies inside a sampled window are
also recorded.

No observed replacement during a finite sample **does not prove finality**. This
tool provides empirical observations for Cisco/BOT engineering to compare with
their authoritative network policy.

## Mainnet 677

The harness fails closed for chain 677:

```bash
python3 scripts/run-bot-network-compatibility.py --chain-id 677
```

To perform read-only RPC observation, the operator must explicitly opt in:

```bash
python3 scripts/run-bot-network-compatibility.py \
  --chain-id 677 \
  --allow-mainnet-read
```

This does not alter NexEscrow's deployment gate. A controlled 677 write/deploy
still requires the separately agreed artifact/asset identity, roles and wallet
control, funding, maximum exposure, stop conditions, and no-customer-funds
boundary.

Execution tracing on 677 additionally requires an explicit transaction evidence
file from a separately approved controlled exercise. The harness will not reuse
Bohr lifecycle transaction hashes as if they were 677 evidence.

## Offline regression tests

The repository's existing tooling CI already runs `python3 -m py_compile
scripts/*.py` and `python3 -m unittest discover -s tests`, so the new scripts and
their safety gates are covered automatically without adding a live RPC
dependency to CI.

The tests verify, offline:

- credential-bearing RPC URLs are rejected;
- 677 fails closed without explicit read opt-in;
- read opt-in never constructs deployment, broadcast, key, or raw-transaction
  commands;
- the recorded 968 deployment target is used by the default plan;
- parent-link inconsistencies are detected;
- execution-trace analysis distinguishes Cancun opcodes and standard precompile
  call targets without treating them as network guarantees.
