import { test } from "node:test";
import assert from "node:assert/strict";

const {
  BOT_RECOMMENDED_LOG_QUERY_BLOCKS,
  RPC_MAX_ATTEMPTS,
  isRetryableRpcError,
  logQueryChunkSizeFor,
  rpcRetryDelayMs,
} = await import(new URL("../rpcPolicy.ts", import.meta.url).href);

test("BOT log queries never exceed the engineering-recommended 2,000-block range", () => {
  assert.equal(BOT_RECOMMENDED_LOG_QUERY_BLOCKS, 2_000n);
  assert.equal(logQueryChunkSizeFor(968), 2_000n);
  assert.equal(logQueryChunkSizeFor(677), 2_000n);
  assert.equal(logQueryChunkSizeFor(968, 50_000n), 2_000n);
  assert.equal(logQueryChunkSizeFor(677, 2_001n), 2_000n);
  assert.equal(logQueryChunkSizeFor(968, 512n), 512n);
});

test("non-BOT networks retain an explicitly requested positive chunk size", () => {
  assert.equal(logQueryChunkSizeFor(3945, 4_000n), 4_000n);
});

test("invalid log query chunk sizes fail closed", () => {
  assert.throws(() => logQueryChunkSizeFor(968, 0n), /Invalid log query chunk size/);
  assert.throws(() => logQueryChunkSizeFor(968, -1n), /Invalid log query chunk size/);
});

test("bounded retry policy recognises transient gateway and transport failures", () => {
  for (const message of [
    "HTTP 429 Too Many Requests",
    "502 Bad Gateway",
    "503 Service Temporarily Unavailable",
    "504 Gateway Timeout",
    "request timed out",
    "network error",
    "fetch failed",
  ]) {
    assert.equal(isRetryableRpcError(new Error(message)), true, message);
  }

  for (const message of [
    "execution reverted",
    "invalid params",
    "method not found",
    "ABI decoding failed",
  ]) {
    assert.equal(isRetryableRpcError(new Error(message)), false, message);
  }
});

test("retry delays are bounded exponential backoff owned by NexEscrow", () => {
  assert.equal(RPC_MAX_ATTEMPTS, 3);
  assert.equal(rpcRetryDelayMs(0), 250);
  assert.equal(rpcRetryDelayMs(1), 500);
  assert.equal(rpcRetryDelayMs(2), 1_000);
  assert.equal(rpcRetryDelayMs(10), 2_000);
  assert.throws(() => rpcRetryDelayMs(-1), /Invalid retry attempt/);
});
