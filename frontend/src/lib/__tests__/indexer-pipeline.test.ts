/**
 * Tests for the production ingestion engine (indexer/pipeline.ts), covering the
 * whitepaper §10.1 checklist with a mock chain and injected RPC sources — no
 * network, deterministic backoff (fixed rng) and instant sleep.
 *
 * Run with:
 *   node --test --experimental-strip-types --no-warnings "src/lib/__tests__/*.test.ts"
 */
import { test } from "node:test";
import assert from "node:assert/strict";

const pipeline = await import(new URL("../indexer/pipeline.ts", import.meta.url).href);
const { createIndexerEngine, MemoryCheckpointStore, MemoryEventSink, computeBackoffMs, adaptWindow, canonicalEventId } =
  pipeline;

interface TestLog {
  transactionHash: string;
  logIndex: number;
  blockNumber: bigint;
  blockHash: string;
  name: string;
  args: Record<string, unknown>;
}
interface IndexedEventLike extends TestLog {
  id: string;
  chainId: number;
  contractAddress: string;
}
interface ChainState {
  hashes: string[];
  logs: TestLog[][];
}
interface RpcErrInfo {
  source: string;
  attempt: number;
  backoffMs: number;
  error: unknown;
}
interface CycleInfo {
  window: bigint;
  logs: number;
}
interface ReorgInfo {
  rolledBackToBlock: bigint;
  depth: bigint;
}

const CONTRACT = "0x1111111111111111111111111111111111111111";
const CHAIN_ID = 968;

function bh(block: number, salt: string): string {
  return "0x" + salt.repeat(60) + block.toString(16).padStart(4, "0");
}
function th(block: number, i: number): string {
  return "0x" + "c".repeat(60) + (block * 100 + i).toString(16).padStart(4, "0");
}
function mkLog(block: number, i: number, salt: string, name = "Funded"): TestLog {
  return {
    transactionHash: th(block, i),
    logIndex: i,
    blockNumber: BigInt(block),
    blockHash: bh(block, salt),
    name,
    args: { block, i },
  };
}

function makeChain(): ChainState {
  return { hashes: [], logs: [] };
}
function extend(chain: ChainState, start: number, end: number, salt: string, eventBlocks: Record<number, number> = {}): void {
  for (let b = start; b <= end; b++) {
    chain.hashes[b] = bh(b, salt);
    const n = eventBlocks[b] ?? 0;
    chain.logs[b] = [];
    for (let i = 0; i < n; i++) chain.logs[b].push(mkLog(b, i, salt));
  }
}
function forkFrom(chain: ChainState, start: number, salt: string, eventBlocks: Record<number, number> = {}): void {
  extend(chain, start, chain.hashes.length - 1, salt, eventBlocks);
}

function makeSource(label: string, chain: ChainState, opts: { failAlways?: boolean } = {}) {
  return {
    label,
    async getBlockNumber(): Promise<bigint> {
      if (opts.failAlways) throw new Error(`${label}: 503`);
      return BigInt(chain.hashes.length - 1);
    },
    async getLogs(from: bigint, to: bigint): Promise<TestLog[]> {
      if (opts.failAlways) throw new Error(`${label}: 503`);
      const out: TestLog[] = [];
      for (let b = Number(from); b <= Number(to) && b < chain.logs.length; b++) {
        out.push(...(chain.logs[b] ?? []));
      }
      return out;
    },
    async getBlockHash(n: bigint): Promise<string> {
      if (opts.failAlways) throw new Error(`${label}: 503`);
      return chain.hashes[Number(n)];
    },
  };
}

const INSTANT = { rng: () => 0.5, sleep: async (): Promise<void> => {} };

function baseConfig(extra: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    chainId: CHAIN_ID,
    contractAddress: CONTRACT,
    deployBlock: 0n,
    confirmations: 0n,
    initialWindow: 2000n,
    ...extra,
  };
}

// ── pure helpers ────────────────────────────────────────────────────────────

test("computeBackoffMs: exponential, capped, jittered within [0.5x, 1x]", () => {
  assert.equal(computeBackoffMs(0, 200, 30_000, () => 0), 100);
  assert.equal(computeBackoffMs(0, 200, 30_000, () => 1), 200);
  assert.equal(computeBackoffMs(3, 200, 30_000, () => 1), 1600);
  assert.equal(computeBackoffMs(20, 200, 30_000, () => 1), 30_000);
  assert.equal(computeBackoffMs(20, 200, 30_000, () => 0), 15_000);
});

test("adaptWindow: shrinks on dense results, grows on sparse, clamps", () => {
  const o = { min: 1n, max: 8n, target: 10 };
  assert.equal(adaptWindow(4n, 20, o), 2n);
  assert.equal(adaptWindow(4n, 1, o), 8n);
  assert.equal(adaptWindow(4n, 5, o), 4n);
  assert.equal(adaptWindow(1n, 100, o), 1n);
});

test("canonicalEventId matches the (chainId:addr:tx:logIndex) formula, lowercased", () => {
  const id = canonicalEventId(968, "0xAbC1111111111111111111111111111111111111", "0xDE" + "a".repeat(62), 2);
  assert.equal(id, "968:0xabc1111111111111111111111111111111111111:0xde" + "a".repeat(62) + ":2");
});

// ── ingestion ─────────────────────────────────────────────────────────────────

test("ingestion is deployment-block scoped", async () => {
  const chain = makeChain();
  extend(chain, 0, 10, "a", { 3: 1, 7: 1 });
  const sink = new MemoryEventSink();
  const engine = createIndexerEngine(baseConfig({ deployBlock: 5n }), [makeSource("rpc", chain)], new MemoryCheckpointStore(), sink, INSTANT);
  await engine.syncToHead();
  const events = (await sink.all()) as IndexedEventLike[];
  assert.equal(events.length, 1, "only the post-deploy event is ingested");
  assert.equal(events[0].blockNumber, 7n);
});

test("idempotent: re-syncing an unchanged chain adds nothing", async () => {
  const chain = makeChain();
  extend(chain, 0, 6, "a", { 2: 2, 5: 1 });
  const sink = new MemoryEventSink();
  const engine = createIndexerEngine(baseConfig(), [makeSource("rpc", chain)], new MemoryCheckpointStore(), sink, INSTANT);
  await engine.syncToHead();
  const first = ((await sink.all()) as IndexedEventLike[]).length;
  assert.equal(first, 3);
  await engine.syncToHead();
  assert.equal(((await sink.all()) as IndexedEventLike[]).length, first, "no duplicates on re-sync");
});

test("confirmations depth: head is not indexed within `confirmations` blocks", async () => {
  const chain = makeChain();
  extend(chain, 0, 10, "a", { 9: 1, 10: 1 });
  const sink = new MemoryEventSink();
  const engine = createIndexerEngine(baseConfig({ confirmations: 3n }), [makeSource("rpc", chain)], new MemoryCheckpointStore(), sink, INSTANT);
  await engine.syncToHead();
  assert.equal(((await sink.all()) as IndexedEventLike[]).length, 0);
});

test("adaptive window shrinks after a dense result", async () => {
  const chain = makeChain();
  const dense: Record<number, number> = { 0: 10 };
  extend(chain, 0, 20, "a", dense);
  const windows: bigint[] = [];
  const engine = createIndexerEngine(
    baseConfig({ initialWindow: 4n, minWindow: 1n, maxWindow: 8n, targetLogsPerWindow: 2 }),
    [makeSource("rpc", chain)],
    new MemoryCheckpointStore(),
    new MemoryEventSink(),
    { ...INSTANT, metrics: { onCycle: (c: CycleInfo) => windows.push(c.window) } },
  );
  await engine.syncToHead();
  assert.equal(windows[0], 2n, "window shrank after dense result");
});

// ── resilience: backoff + failover ──────────────────────────────────────────────

test("fails over to a healthy RPC source after a dead one, recording errors", async () => {
  const chain = makeChain();
  extend(chain, 0, 4, "a", { 1: 1, 3: 1 });
  const errors: RpcErrInfo[] = [];
  const sink = new MemoryEventSink();
  const engine = createIndexerEngine(
    baseConfig({ maxAttemptsPerSource: 3 }),
    [makeSource("dead", chain, { failAlways: true }), makeSource("live", chain)],
    new MemoryCheckpointStore(),
    sink,
    { ...INSTANT, metrics: { onRpcError: (e: RpcErrInfo) => errors.push(e) } },
  );
  await engine.syncToHead();
  assert.equal(((await sink.all()) as IndexedEventLike[]).length, 2, "ingested via the live source");
  assert.ok(errors.length >= 3, "retried the dead source with backoff before failover");
  assert.ok(errors.every((e) => e.source === "dead"));
  assert.ok(errors.some((e) => e.backoffMs > 0));
});

// ── reorg detection + rollback ───────────────────────────────────────────────────

test("reorg: detects a changed block hash, rolls back and re-ingests the new fork", async () => {
  const chain = makeChain();
  extend(chain, 0, 10, "a", { 2: 1, 7: 1, 9: 1 });
  const sink = new MemoryEventSink();
  const reorgs: ReorgInfo[] = [];
  const engine = createIndexerEngine(
    baseConfig({ recentHashDepth: 256 }),
    [makeSource("rpc", chain)],
    new MemoryCheckpointStore(),
    sink,
    { ...INSTANT, metrics: { onReorg: (r: ReorgInfo) => reorgs.push(r) } },
  );
  await engine.syncToHead();
  const before = (await sink.all()) as IndexedEventLike[];
  assert.deepEqual(before.map((e) => Number(e.blockNumber)), [2, 7, 9]);
  assert.ok(before.every((e) => e.blockHash.startsWith("0xaaaa")));

  forkFrom(chain, 6, "b", { 7: 1, 8: 1 });
  await engine.syncToHead();

  assert.equal(reorgs.length, 1, "exactly one reorg handled");
  const after = (await sink.all()) as IndexedEventLike[];
  assert.deepEqual(after.map((e) => Number(e.blockNumber)), [2, 7, 8]);
  assert.ok(after.filter((e) => e.blockNumber < 6n).every((e) => e.blockHash.startsWith("0xaaaa")));
  assert.ok(after.filter((e) => e.blockNumber >= 6n).every((e) => e.blockHash.startsWith("0xbbbb")));
});

// ── reproducible rebuild ─────────────────────────────────────────────────────────

test("rebuild from deploy block reproduces the same event set", async () => {
  const chain = makeChain();
  extend(chain, 0, 12, "a", { 1: 2, 4: 1, 11: 3 });
  const incSink = new MemoryEventSink();
  const incEngine = createIndexerEngine(baseConfig({ initialWindow: 3n }), [makeSource("rpc", chain)], new MemoryCheckpointStore(), incSink, INSTANT);
  await incEngine.syncToHead();
  await incEngine.rebuild();
  const rebuilt = ((await incSink.all()) as IndexedEventLike[]).map((e) => `${e.id}@${e.blockHash}`);

  const freshSink = new MemoryEventSink();
  const freshEngine = createIndexerEngine(baseConfig({ initialWindow: 1000n }), [makeSource("rpc", chain)], new MemoryCheckpointStore(), freshSink, INSTANT);
  await freshEngine.syncToHead();
  const fresh = ((await freshSink.all()) as IndexedEventLike[]).map((e) => `${e.id}@${e.blockHash}`);

  assert.deepEqual(rebuilt, fresh, "rebuild is window-independent and reproducible");
  assert.equal(rebuilt.length, 6);
});
