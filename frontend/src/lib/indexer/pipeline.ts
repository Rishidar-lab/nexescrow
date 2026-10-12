/**
 * Production ingestion engine for the NexEscrow Demo 1 indexer (whitepaper §10.1).
 *
 * The browser `logScan` adapter is a degraded-mode fallback; this is the hosted,
 * mainnet-grade path. It is deliberately self-contained (only `import type` from
 * viem, which strip-types erases) so it runs directly under
 * `node --test --experimental-strip-types`, matching this package's test runner.
 *
 * All I/O is injected, so the whole §10.1 checklist is testable without a network:
 *   - deployment-block-scoped ingestion;
 *   - adaptive bounded windows (grow on small results, shrink on large/errors);
 *   - exponential backoff + jitter on RPC errors (5xx / rate limits);
 *   - provider failover across multiple RPC sources;
 *   - idempotent event key (chainId, contractAddress, txHash, logIndex);
 *   - transactional checkpoints;
 *   - block-hash reorg detection and rollback;
 *   - ingestion-lag / RPC-error / decode-error monitoring hooks;
 *   - reproducible full rebuild from the deploy block.
 */
import type { Address, Hex } from "viem";

// ---------------------------------------------------------------------------
// Event identity — mirrors indexer/types.ts `eventId` (kept inline so this
// module has no runtime relative import; the formula MUST stay identical).
// ---------------------------------------------------------------------------

export interface RawLog {
  transactionHash: Hex;
  logIndex: number;
  blockNumber: bigint;
  blockHash: Hex;
  name: string;
  args: Record<string, unknown>;
}

export interface IndexedEvent extends RawLog {
  /** Idempotency key: `${chainId}:${address}:${txHash}:${logIndex}` (lowercased). */
  id: string;
  chainId: number;
  contractAddress: Address;
}

export function canonicalEventId(
  chainId: number,
  contractAddress: Address,
  transactionHash: Hex,
  logIndex: number,
): string {
  return [chainId, contractAddress.toLowerCase(), transactionHash.toLowerCase(), logIndex].join(":");
}

/** Structural guard: a RawLog that is missing/garbled is a DECODE error, not fatal. */
function isWellFormedLog(log: unknown): log is RawLog {
  if (typeof log !== "object" || log === null) return false;
  const l = log as Record<string, unknown>;
  return (
    typeof l.transactionHash === "string" &&
    /^0x[0-9a-fA-F]{64}$/.test(l.transactionHash) &&
    typeof l.blockHash === "string" &&
    /^0x[0-9a-fA-F]{64}$/.test(l.blockHash) &&
    typeof l.logIndex === "number" &&
    Number.isSafeInteger(l.logIndex) &&
    l.logIndex >= 0 &&
    typeof l.blockNumber === "bigint" &&
    typeof l.name === "string" &&
    l.name.length > 0 &&
    typeof l.args === "object" &&
    l.args !== null
  );
}

// ---------------------------------------------------------------------------
// Injected boundaries
// ---------------------------------------------------------------------------

export interface RpcSource {
  readonly label: string;
  getBlockNumber(): Promise<bigint>;
  getLogs(fromBlock: bigint, toBlock: bigint): Promise<RawLog[]>;
  getBlockHash(blockNumber: bigint): Promise<Hex>;
}

export interface Checkpoint {
  chainId: number;
  contractAddress: Address;
  /** Highest fully-ingested block (deployBlock-1 means "nothing yet"). */
  lastBlock: bigint;
  /** Recent (blockNumber -> blockHash) for reorg detection; bounded. */
  recentHashes: Array<{ block: bigint; hash: Hex }>;
}

export interface CheckpointStore {
  load(): Promise<Checkpoint | null>;
  /** Atomic replace — a crash mid-save must never leave a torn checkpoint. */
  save(checkpoint: Checkpoint): Promise<void>;
}

export interface EventSink {
  /** Insert events, ignoring any whose `id` is already present (idempotent). */
  upsert(events: IndexedEvent[]): Promise<void>;
  /** Remove every event at `blockNumber >= fromBlock` (reorg rollback). */
  rollbackFrom(fromBlock: bigint): Promise<void>;
  all(): Promise<IndexedEvent[]>;
}

export interface IndexerMetrics {
  onCycle?(info: { fromBlock: bigint; toBlock: bigint; window: bigint; logs: number; lag: bigint }): void;
  onRpcError?(info: { source: string; attempt: number; backoffMs: number; error: unknown }): void;
  onReorg?(info: { rolledBackToBlock: bigint; depth: bigint }): void;
  onDecodeError?(info: { count: number }): void;
}

export interface EngineConfig {
  chainId: number;
  contractAddress: Address;
  deployBlock: bigint;
  minWindow?: bigint;
  maxWindow?: bigint;
  initialWindow?: bigint;
  targetLogsPerWindow?: number;
  /** Reorg-safety depth: never index within this many blocks of the head. */
  confirmations?: bigint;
  maxAttemptsPerSource?: number;
  baseBackoffMs?: number;
  maxBackoffMs?: number;
  recentHashDepth?: number;
}

export interface EngineDeps {
  metrics?: IndexerMetrics;
  /** Injectable for deterministic tests (defaults to Math.random). */
  rng?: () => number;
  /** Injectable for instant tests (defaults to real setTimeout). */
  sleep?: (ms: number) => Promise<void>;
}

// ---------------------------------------------------------------------------
// Pure helpers (independently testable)
// ---------------------------------------------------------------------------

/** Full-jitter exponential backoff, capped. `attempt` is 0-based. */
export function computeBackoffMs(
  attempt: number,
  baseMs: number,
  capMs: number,
  rng: () => number,
): number {
  const exp = Math.min(capMs, baseMs * 2 ** attempt);
  return Math.floor(exp * (0.5 + 0.5 * rng()));
}

/** Grow the window when results are sparse, shrink it when dense; always clamped. */
export function adaptWindow(
  current: bigint,
  logCount: number,
  opts: { min: bigint; max: bigint; target: number },
): bigint {
  let next = current;
  if (logCount > opts.target) {
    next = current / 2n;
  } else if (logCount * 4 < opts.target) {
    next = current * 2n;
  }
  if (next < opts.min) next = opts.min;
  if (next > opts.max) next = opts.max;
  return next;
}

// ---------------------------------------------------------------------------
// In-memory stores (reference implementations; a hosted deployment swaps these
// for a transactional DB — the interfaces are the contract)
// ---------------------------------------------------------------------------

export class MemoryCheckpointStore implements CheckpointStore {
  private current: Checkpoint | null = null;
  async load(): Promise<Checkpoint | null> {
    return this.current ? structuredClone(this.current) : null;
  }
  async save(checkpoint: Checkpoint): Promise<void> {
    this.current = structuredClone(checkpoint);
  }
}

export class MemoryEventSink implements EventSink {
  private readonly byId = new Map<string, IndexedEvent>();
  async upsert(events: IndexedEvent[]): Promise<void> {
    for (const e of events) {
      if (!this.byId.has(e.id)) this.byId.set(e.id, e);
    }
  }
  async rollbackFrom(fromBlock: bigint): Promise<void> {
    for (const [id, e] of this.byId) {
      if (e.blockNumber >= fromBlock) this.byId.delete(id);
    }
  }
  async all(): Promise<IndexedEvent[]> {
    return [...this.byId.values()].sort(
      (a, b) => Number(a.blockNumber - b.blockNumber) || a.logIndex - b.logIndex,
    );
  }
}

// ---------------------------------------------------------------------------
// Engine
// ---------------------------------------------------------------------------

export interface CycleResult {
  advanced: boolean;
  fromBlock: bigint;
  toBlock: bigint;
  reorg: boolean;
  caughtUp: boolean;
}

export function createIndexerEngine(
  config: EngineConfig,
  sources: RpcSource[],
  store: CheckpointStore,
  sink: EventSink,
  deps: EngineDeps = {},
) {
  if (sources.length === 0) throw new Error("at least one RPC source is required");
  const cfg = {
    minWindow: 1n,
    maxWindow: 10_000n,
    initialWindow: 2_000n,
    targetLogsPerWindow: 500,
    confirmations: 12n,
    maxAttemptsPerSource: 4,
    baseBackoffMs: 200,
    maxBackoffMs: 30_000,
    recentHashDepth: 256,
    ...config,
  };
  const metrics = deps.metrics ?? {};
  const rng = deps.rng ?? Math.random;
  const sleep = deps.sleep ?? ((ms: number) => new Promise<void>((r) => setTimeout(r, ms)));

  let window = cfg.initialWindow;

  function freshCheckpoint(): Checkpoint {
    return {
      chainId: cfg.chainId,
      contractAddress: cfg.contractAddress,
      lastBlock: cfg.deployBlock - 1n,
      recentHashes: [],
    };
  }

  /** Try each source in order; retry a source with backoff+jitter before failing over. */
  async function withResilience<T>(op: (source: RpcSource) => Promise<T>): Promise<T> {
    let lastError: unknown;
    for (const source of sources) {
      for (let attempt = 0; attempt < cfg.maxAttemptsPerSource; attempt++) {
        try {
          return await op(source);
        } catch (error) {
          lastError = error;
          const backoffMs = computeBackoffMs(attempt, cfg.baseBackoffMs, cfg.maxBackoffMs, rng);
          metrics.onRpcError?.({ source: source.label, attempt, backoffMs, error });
          if (attempt + 1 < cfg.maxAttemptsPerSource) await sleep(backoffMs);
        }
      }
    }
    throw lastError instanceof Error ? lastError : new Error("all RPC sources failed");
  }

  function pruneHashes(cp: Checkpoint): void {
    const floor = cp.lastBlock - BigInt(cfg.recentHashDepth);
    cp.recentHashes = cp.recentHashes
      .filter((h) => h.block > floor)
      .sort((a, b) => Number(a.block - b.block));
  }

  /** Detect a reorg by comparing stored block hashes with the chain; roll back if needed. */
  async function reconcileReorg(cp: Checkpoint): Promise<boolean> {
    if (cp.recentHashes.length === 0) return false;
    const desc = [...cp.recentHashes].sort((a, b) => Number(b.block - a.block));
    // Tip still canonical?
    const tip = desc[0];
    if ((await withResilience((s) => s.getBlockHash(tip.block))) === tip.hash) return false;
    // Walk back to the deepest still-matching ancestor.
    let ancestor = cfg.deployBlock - 1n;
    for (const { block, hash } of desc) {
      if ((await withResilience((s) => s.getBlockHash(block))) === hash) {
        ancestor = block;
        break;
      }
    }
    const depth = cp.lastBlock - ancestor;
    await sink.rollbackFrom(ancestor + 1n);
    cp.lastBlock = ancestor;
    cp.recentHashes = cp.recentHashes.filter((h) => h.block <= ancestor);
    await store.save(cp);
    metrics.onReorg?.({ rolledBackToBlock: ancestor, depth });
    return true;
  }

  function mapLogs(logs: RawLog[]): IndexedEvent[] {
    const out: IndexedEvent[] = [];
    let decodeErrors = 0;
    for (const log of logs) {
      if (!isWellFormedLog(log)) {
        decodeErrors++;
        continue;
      }
      out.push({
        ...log,
        chainId: cfg.chainId,
        contractAddress: cfg.contractAddress,
        id: canonicalEventId(cfg.chainId, cfg.contractAddress, log.transactionHash, log.logIndex),
      });
    }
    if (decodeErrors > 0) metrics.onDecodeError?.({ count: decodeErrors });
    // Idempotent within the batch too.
    const seen = new Set<string>();
    return out.filter((e) => (seen.has(e.id) ? false : (seen.add(e.id), true)));
  }

  async function syncOnce(): Promise<CycleResult> {
    let cp = (await store.load()) ?? freshCheckpoint();

    const reorg = await reconcileReorg(cp);
    if (reorg) cp = (await store.load()) ?? cp;

    const head = await withResilience((s) => s.getBlockNumber());
    const safeHead = head - cfg.confirmations;
    const fromBlock = cp.lastBlock + 1n < cfg.deployBlock ? cfg.deployBlock : cp.lastBlock + 1n;

    if (fromBlock > safeHead) {
      metrics.onCycle?.({ fromBlock, toBlock: cp.lastBlock, window, logs: 0, lag: 0n });
      return { advanced: false, fromBlock, toBlock: cp.lastBlock, reorg, caughtUp: true };
    }

    const toBlock = safeHead < fromBlock + window - 1n ? safeHead : fromBlock + window - 1n;
    const logs = await withResilience((s) => s.getLogs(fromBlock, toBlock));
    const events = mapLogs(logs);
    await sink.upsert(events);

    // Record block hashes for reorg detection: every event-bearing block (free from
    // the logs) plus the window's end (fetched once).
    for (const e of events) {
      cp.recentHashes.push({ block: e.blockNumber, hash: e.blockHash });
    }
    cp.recentHashes.push({ block: toBlock, hash: await withResilience((s) => s.getBlockHash(toBlock)) });
    cp.lastBlock = toBlock;
    pruneHashes(cp);
    await store.save(cp);

    window = adaptWindow(window, logs.length, {
      min: cfg.minWindow,
      max: cfg.maxWindow,
      target: cfg.targetLogsPerWindow,
    });
    metrics.onCycle?.({ fromBlock, toBlock, window, logs: logs.length, lag: head - toBlock });
    return { advanced: true, fromBlock, toBlock, reorg, caughtUp: toBlock >= safeHead };
  }

  async function syncToHead(maxCycles = 100_000): Promise<void> {
    for (let i = 0; i < maxCycles; i++) {
      const r = await syncOnce();
      if (!r.advanced || r.caughtUp) return;
    }
    throw new Error("syncToHead exceeded maxCycles — not converging");
  }

  /** Reproducible full rebuild from the deploy block: wipe and re-ingest. */
  async function rebuild(): Promise<void> {
    await sink.rollbackFrom(0n);
    await store.save(freshCheckpoint());
    window = cfg.initialWindow;
    await syncToHead();
  }

  return { syncOnce, syncToHead, rebuild };
}
