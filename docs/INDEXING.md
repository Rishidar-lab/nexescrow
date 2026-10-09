# Agreement Indexing Architecture

> Scope: how NexEscrow turns on-chain events into UI/API state. The contract is the
> source of truth; the index is a derived, rebuildable cache.

## 1. Event identity

An escrow event is uniquely identified across the entire multi-chain deployment by:

```
(chainId, contractAddress, transactionHash, logIndex)
```

This is the one and only idempotency key. `transactionHash` alone is **not** unique
across chains, and a single transaction can emit multiple escrow logs
(`AgreementCreated` + `Funded` can land in one multicall; `MilestoneReleased` and
`AgreementCompleted` are emitted from the same call). The implementation lives in
`frontend/src/lib/indexer/types.ts` (`eventId()`), and the direct-RPC adapter dedupes
on exactly this key.

## 2. Adapter boundary (what exists today)

`AgreementIndexAdapter` (`frontend/src/lib/indexer/types.ts`) exposes:

- `discoverAgreementsForParticipant(address)`
- `eventsForAgreement(agreementId)`
- `stats()`

Two implementations:

| Adapter | File | Use |
|---|---|---|
| `log-scan` | `frontend/src/lib/indexer/logScan.ts` | Default. Bounded, chunked `eth_getLogs` straight to RPC. No infrastructure. Works at testnet scale. |
| `http` | `frontend/src/lib/indexer/http.ts` | Production path. Talks to an indexer service implementing §4. Enabled by setting `NEXT_PUBLIC_INDEXER_URL`. |

The UI never talks to a specific backend directly; it consumes the interface. Swapping
adapters is a config change, not a UI change.

### 2.1 `log-scan` guarantees

- **Bounded RPC queries** — scans in `chunkSize` windows (default 2,000 blocks) from
  the deployment block (`NEXT_PUBLIC_DEPLOY_BLOCK_<chainId>`); never a single
  unbounded `fromBlock: 0` query.
- **Idempotent + deduped** — records are keyed by the four-part identity; repeated
  scans replace rather than append.
- **Confirmed-block checkpoint** — the head used for a scan is
  `latest - confirmations` (default 12). A checkpoint block is persisted per
  `(chainId, contract)` in `localStorage` for observability; the authoritative resume
  state is the in-memory record cache.
- **Reorg reconciliation** — each sync rebuilds the record set from the deploy block
  and replaces the cache, so orphaned logs disappear instead of lingering. Because
  checkpoints never advance past the confirmed head, a reorg deeper than the
  confirmation window is re-scanned on the next sync.
- **Chain + contract separation** — cache keys are `chainId:contractAddress`, and the
  adapter refuses a `PublicClient` whose chain does not match its configuration.
- **Honest stats** — `stats()` returns `null`; the client scan does not pretend to
  compute protocol-wide aggregates. Stat panels hide rather than fabricate numbers.

The log scan is explicitly a testnet-scale mechanism. A chain with millions of blocks
and many agreements needs the HTTP indexer for bounded latency and query cost.

## 3. Canonical event set

| Event | Indexed fields | Used for |
|---|---|---|
| `AgreementCreated(id, buyer, seller, arbiter, token, totalAmount, feeBps, fundingDeadline, milestoneAmounts)` | `id`, `buyer`, `seller` | discovery, initial state |
| `Funded(id)` | `id` | activation |
| `MilestoneReleased(id, milestoneIndex, amount, fee)` | `id`, `milestoneIndex` | payout history |
| `DisputeRaised(id, milestoneIndex, raisedBy)` | `id`, `milestoneIndex`, `raisedBy` | dispute history |
| `DisputeResolved(id, milestoneIndex, buyerBps, buyerAmount, sellerAmount, fee)` | `id`, `milestoneIndex` | settlement history |
| `AgreementCancelled(id)` | `id` | terminal state |
| `AgreementCompleted(id)` | `id` | terminal state |
| `FeesWithdrawn(token, to, amount)` | `token`, `to` | fee accounting |
| `ProtocolFeeUpdated(oldBps, newBps)` | — | admin history |
| `FeeRecipientUpdated(oldRecipient, newRecipient)` | — | admin history |

Only `id`, `buyer`, `seller`, `milestoneIndex`, `raisedBy`, `token`, and `to` are
indexed topics; all other fields are decoded from data. The contract does **not** emit a
timestamp for every event — indexers should attach `blockTimestamp` at ingestion time
and treat it as derived data.

## 4. Production indexer contract

### 4.1 Ingestion pipeline

1. **Range fetcher** — for each `(chainId, contractAddress)`, fetch logs in bounded
   ranges (hard cap, e.g. 2,000 blocks) with retry/backoff and per-RPC rate limiting.
   Start at the recorded deployment block; never scan from genesis.
2. **Decoder** — decode with the canonical ABI (`frontend/src/lib/nexusEscrowAbi.ts`
   is generated from the artifact; the service should consume
   `contracts/out/NexusEscrow.sol/NexusEscrow.json` or an ABI registry keyed by
   `(chainId, address, codeHash)`).
3. **Idempotent upsert** — store rows keyed by
   `(chain_id, contract_address, tx_hash, log_index)` with a unique constraint; an
   `INSERT … ON CONFLICT DO NOTHING` is the entire duplicate-prevention mechanism.
4. **Checkpoint** — after a range is committed and is at least `confirmations` deep,
   advance `(chain_id, contract_address) → last_confirmed_block`. Checkpoints are
   monotonic and transactional with the rows they cover.
5. **Reorg reconciliation** — store `block_hash` with every event and the canonical
   hash per height. On each head update, walk back from the tip; if a stored
   `block_hash` differs from the canonical one, delete rows for the orphaned heights
   and re-fetch from the reorg point. Never trust `removed` flags alone.
6. **Chain separation / contract separation** — every table is keyed by
   `chain_id` and `contract_address`. Multi-chain deployments of the same bytecode are
   distinct datasets; a re-org or backfill on one chain must never touch another.

### 4.2 Suggested schema (Postgres)

```sql
CREATE TABLE escrow_events (
  chain_id          INTEGER     NOT NULL,
  contract_address  BYTEA       NOT NULL,
  tx_hash           BYTEA       NOT NULL,
  log_index         INTEGER     NOT NULL,
  block_number      BIGINT      NOT NULL,
  block_hash        BYTEA       NOT NULL,
  event_name        TEXT        NOT NULL,
  agreement_id      NUMERIC,
  args              JSONB       NOT NULL,
  PRIMARY KEY (chain_id, contract_address, tx_hash, log_index)
);

CREATE TABLE indexer_checkpoints (
  chain_id          INTEGER NOT NULL,
  contract_address  BYTEA   NOT NULL,
  last_confirmed_block BIGINT NOT NULL,
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (chain_id, contract_address)
);

CREATE INDEX escrow_events_agreement
  ON escrow_events (chain_id, contract_address, agreement_id, block_number, log_index);
```

### 4.3 HTTP API contract

```
GET /v1/chains/{chainId}/contracts/{address}/agreements?participant=0x…
GET /v1/chains/{chainId}/contracts/{address}/agreements/{id}/events
GET /v1/chains/{chainId}/contracts/{address}/stats
```

Event response items must carry their full identity
(`chainId`, `contractAddress`, `transactionHash`, `logIndex`, `blockNumber`,
`blockHash`, `name`, `args`). The frontend HTTP adapter re-validates
`chainId`/`contractAddress` and drops mismatches (defense in depth against a
misconfigured or compromised indexer).

### 4.4 Confirmations by chain

`confirmations` is policy, not a constant: set per chain from its finality model.
The frontend default is 12 for log-scan reorg safety; the indexer should use the
chain's recommended finality depth (and document it). BOT Chain's recommended depth
should be confirmed with BOT Chain engineers — tracked in
`docs/BOTCHAIN_INTEGRATION.md` §20.

## 5. Operational requirements

- **Monitoring**: ingestion lag per `(chainId, contractAddress)`, checkpoint age,
  decode failures, RPC error rate.
- **Backfill**: replay from the deployment block; the pipeline is idempotent by design.
- **Chain-specific deploy blocks**: stored alongside the contract address, never
  hardcoded.
- **No client trust**: the UI must remain functional read-only against RPC if the
  indexer is down (the default adapter is the log scan).

## 6. Measured BOT RPC capability (2026-10-08)

Empirical validation (raw data: `docs/evidence/bot-rpc-capability.json`; write-up:
`docs/evidence/bot-rpc-capability.md`) found:

- `eth_getLogs` is **enabled and functional** on both `rpc.bohr.life` (968) and
  `rpc.botchain.ai` (677), contrary to the published statement that it is disabled.
- No hard server-side range cap: empty-filter scans of ~full history succeeded
  (~0.6 s mainnet, ~3 s Bohr). Reliability is governed by result volume: mainnet
  Wrapped-BOT logs grew to 12,365 results over a 64,000-block range (~4 s).
- Intermittent nginx 503s were observed once on Bohr; retry-with-backoff is required.

**Indexing decision (Task 2 classification): B - bounded-block-window polling**, with
A technically viable today. No redesign is warranted: the existing log-scan adapter
already implements bounded windows, dedupe by the four-part event identity, a
confirmed-block checkpoint and rescan-based reorg handling. The measured evidence
supports keeping it; the HTTP adapter remains the opt-in fallback if the method is
ever disabled. The default 2,000-block chunk is conservative and sits far below any
measured acceptance limit, while keeping per-query payload small on a busy mainnet
(≈262 logs for a busy token at 2,000 blocks, under 1 s).

## 7. What this sprint deliberately did not build

A hosted indexer, a database, a queue, or a reorg daemon. The interface boundary plus a
correct bounded client scan is sufficient for the current testnet stage; building the
service without a deployed contract to index would be speculative infrastructure. The
production path above is the specification for whoever operates the first real
deployment.
