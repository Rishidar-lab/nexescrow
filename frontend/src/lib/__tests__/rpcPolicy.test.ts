import { test } from "node:test";
import assert from "node:assert/strict";
import { HttpRequestError, RpcRequestError, TimeoutError } from "viem";

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

test("bounded retry policy recognises only the allowlisted typed HTTP and timeout failures", () => {
  for (const status of [429, 502, 503, 504]) {
    const error = new HttpRequestError({
      status,
      url: "https://rpc.example.invalid",
    });
    assert.equal(isRetryableRpcError(error), true, `HTTP ${status}`);
  }

  assert.equal(
    isRetryableRpcError(
      new TimeoutError({ body: { method: "eth_getLogs", params: [] }, url: "https://rpc.example.invalid" }),
    ),
    true,
  );

  for (const status of [400, 401, 403, 404, 500, 501, 505]) {
    const error = new HttpRequestError({
      status,
      url: "https://rpc.example.invalid",
    });
    assert.equal(isRetryableRpcError(error), false, `HTTP ${status}`);
  }
});

test("bounded retry policy retains a narrow plain transport-error fallback", () => {
  for (const message of ["network error", "fetch failed", "failed to fetch"]) {
    assert.equal(isRetryableRpcError(new Error(message)), true, message);
  }

  for (const message of ["execution reverted", "invalid params", "method not found", "HTTP 503"]) {
    assert.equal(isRetryableRpcError(new Error(message)), false, message);
  }
});

test("permanent typed RPC errors are never retried even when their text contains gateway codes", () => {
  for (const statusText of ["429", "502", "503", "504"]) {
    const error = new RpcRequestError({
      body: { method: "eth_getLogs", params: [] },
      error: { code: -32602, message: `invalid params: supplied value contains ${statusText}` },
      url: "https://rpc.example.invalid",
    });
    assert.equal(isRetryableRpcError(error), false, statusText);
    assert.equal(isRetryableRpcError(new Error("outer", { cause: error })), false, statusText);
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
