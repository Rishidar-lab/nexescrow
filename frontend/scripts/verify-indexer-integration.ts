/**
 * Read-only adapter integration checks (fixture-backed, not a browser/live RPC test).
 * From frontend/:
 * pnpm dlx esbuild@0.28.2 scripts/verify-indexer-integration.ts --bundle --platform=node --format=esm --outfile=/tmp/nexescrow-indexer-check.mjs
 * node /tmp/nexescrow-indexer-check.mjs
 * Uses a local HTTP fixture server and isolated child processes for reloads.
 */
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createServer } from "node:http";
import { spawnSync } from "node:child_process";
import { decodeEventLog, type Address, type PublicClient } from "viem";
import { escrowAbi } from "../src/lib/contract";
import { createLogScanAdapter } from "../src/lib/indexer/logScan";
import { createHttpIndexerAdapter } from "../src/lib/indexer/http";

const fixture = JSON.parse(readFileSync("../docs/evidence/bot-968/events.json", "utf8"));
const address = fixture.address as Address;
const start = 26178651n;
const latest = BigInt(fixture.toBlock) + 4012n;
const key = `nexescrow:logscan:v1:968:${address.toLowerCase()}`;
const logs = fixture.logs.map((log: Record<string, unknown>) => ({
  ...log,
  ...decodeEventLog({ abi: escrowAbi, data: log.data as `0x${string}`, topics: log.topics as [`0x${string}`, ...`0x${string}`[]] }),
  blockNumber: BigInt(log.blockNumber as string),
  logIndex: Number(BigInt(log.logIndex as string)),
}));

async function replay() {
  const storage = new Map<string, string>();
  if (process.env.REPLAY_CHECKPOINT) storage.set(key, process.env.REPLAY_CHECKPOINT);
  Object.defineProperty(globalThis, "window", { value: { localStorage: {
    getItem: (name: string) => storage.get(name) ?? null,
    setItem: (name: string, value: string) => storage.set(name, value),
  } }, configurable: true });
  const ranges: string[][] = [];
  const client = {
    chain: { id: 968 },
    getBlockNumber: async () => latest,
    getContractEvents: async ({ fromBlock, toBlock }: { fromBlock: bigint; toBlock: bigint }) => {
      assert(toBlock - fromBlock + 1n <= 2000n);
      ranges.push([String(fromBlock), String(toBlock)]);
      const matches = logs.filter((log: { blockNumber: bigint }) => log.blockNumber >= fromBlock && log.blockNumber <= toBlock);
      return matches.length ? [...matches, matches[0]] : matches; // deliberate duplicate
    },
  } as unknown as PublicClient;
  const adapter = createLogScanAdapter({ chainId: 968, contractAddress: address, publicClient: client, startBlock: start });
  const events = [...await adapter.eventsForAgreement(0n), ...await adapter.eventsForAgreement(1n)];
  const ids = events.map(event => event.id).sort();
  assert.equal(new Set(ids).size, ids.length);
  const expected = logs.filter((log: { args?: { id?: bigint } }) => typeof log.args?.id === "bigint").map((log: { transactionHash: string; logIndex: number }) => `968:${address.toLowerCase()}:${log.transactionHash.toLowerCase()}:${log.logIndex}`).sort();
  assert.deepEqual(ids, expected);
  assert.equal(ranges[0][0], String(start));
  assert.equal(storage.get(key), String(latest - 12n + 1n));
  console.log(JSON.stringify({ ids, ranges, checkpoint: storage.get(key), fixtureLogs: logs.length }));
}

async function main() {
  const stages = [undefined, String(latest - 12n + 1n), undefined];
  const outputs = stages.map(checkpoint => {
    const env = { ...process.env };
    delete env.REPLAY_CHECKPOINT;
    if (checkpoint) env.REPLAY_CHECKPOINT = checkpoint;
    const result = spawnSync(process.execPath, [process.argv[1], "--replay"], { env, encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr);
    return JSON.parse(result.stdout);
  });
  assert.deepEqual(outputs[0], outputs[1]);
  assert.deepEqual(outputs[0], outputs[2]);
  const buyer = "0x1111111111111111111111111111111111111111" as Address;
  const seller = "0x2222222222222222222222222222222222222222";
  const arbiter = "0x3333333333333333333333333333333333333333";
  const valid = { chainId: 968, contractAddress: address, id: "0", buyer, seller, arbiter };
  const requests: string[] = [];
  const server = createServer((req, res) => {
    requests.push(req.url ?? "");
    res.setHeader("Content-Type", "application/json");
    res.end(JSON.stringify([valid, { ...valid, chainId: 677, id: "1" }, { ...valid, contractAddress: seller, id: "2" }, { id: "3", buyer, seller, arbiter }]));
  });
  await new Promise<void>(resolve => server.listen(0, "127.0.0.1", resolve));
  try {
    const endpoint = server.address();
    assert(endpoint && typeof endpoint !== "string");
    const adapter = createHttpIndexerAdapter({ baseUrl: `http://127.0.0.1:${endpoint.port}`, chainId: 968, contractAddress: address });
    const rows = await adapter.discoverAgreementsForParticipant(buyer);
    assert.deepEqual(rows.map(row => String(row.id)), ["0"]);
    assert.equal(requests.length, 1);
    assert(requests[0].startsWith(`/v1/chains/968/contracts/${address.toLowerCase()}/agreements?participant=`));
  } finally {
    await new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
  }
  console.log(JSON.stringify({ status: "PASS", source: "committed historical Bohr fixture + local HTTP server", replayStages: ["cold process", "new process with persisted checkpoint", "new process with cleared checkpoint"], agreementEvents: outputs[0].ids.length, fixtureLogs: outputs[0].fixtureLogs, rangesPerReplay: outputs[0].ranges, httpScope: "valid retained; wrong chain, wrong contract and legacy unscoped rows rejected", browser: "NOT TESTED", liveRpc: "NOT TESTED", transactions: 0 }, null, 2));
}

await (process.argv.includes("--replay") ? replay() : main());
