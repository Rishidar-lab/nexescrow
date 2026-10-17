/**
 * Regression tests for the indexer's row validation.
 *
 * `http.ts` documents that "the adapter re-checks chainId and contractAddress
 * and drops anything that does not match, so a misconfigured indexer cannot
 * leak another chain's agreements into this UI". Before these tests that claim
 * was only true of the *event* path, and even there it threw before it could
 * drop anything: a missing `contractAddress` hit `.toLowerCase()` on undefined
 * and a malformed `blockNumber` hit `BigInt()`.
 *
 * These assert the boundary directly, with the malformed shapes an indexer (or
 * something impersonating one) can actually return.
 *
 * Run with:
 *   node --test --experimental-strip-types --no-warnings "src/lib/__tests__/*.test.ts"
 */
import { test } from "node:test";
import assert from "node:assert/strict";

const { isDiscoveryRowForScope, isValidDiscoveryRow, isValidEventRow } = await import(
  new URL("../indexer/validate.ts", import.meta.url).href
);

const { dedupeEvents, dedupeDiscoveries } = await import(
  new URL("../indexer/types.ts", import.meta.url).href
);

const ADDRESS_A = "0x1111111111111111111111111111111111111111";
const ADDRESS_B = "0x2222222222222222222222222222222222222222";
const ADDRESS_C = "0x3333333333333333333333333333333333333333";
const HASH = "0x" + "ab".repeat(32);

// ── discovery rows ────────────────────────────────────────────────────────────

test("accepts a well-formed discovery row", () => {
  assert.equal(
    isValidDiscoveryRow({
      chainId: 968,
      contractAddress: ADDRESS_A,
      id: "0",
      buyer: ADDRESS_A,
      seller: ADDRESS_B,
      arbiter: ADDRESS_C,
    }),
    true,
  );
});

test("CRITICAL: rejects a non-array payload instead of throwing", () => {
  // The adapter returns [] when the body is an object, not an array.
  for (const bad of [{}, { error: "not authorized" }, "oops", 42, null]) {
    assert.equal(isValidDiscoveryRow(bad), false, `must reject ${JSON.stringify(bad)}`);
  }
});

test("CRITICAL: rejects rows whose addresses are missing or malformed", () => {
  // These would previously reach `.toLowerCase()` in useMyAgreements and throw
  // inside useMemo, taking the dashboard down.
  const base = {
    chainId: 968,
    contractAddress: ADDRESS_A,
    id: "1",
    buyer: ADDRESS_A,
    seller: ADDRESS_B,
    arbiter: ADDRESS_C,
  };
  const bads = [
    { ...base, buyer: undefined },
    { ...base, seller: null },
    { ...base, arbiter: 123 },
    { ...base, buyer: "0xnothex" },
    { ...base, seller: ADDRESS_A.slice(0, 39) },
    { ...base, arbiter: ADDRESS_A + "00" },
    { ...base, seller: "example.com" },
  ];
  for (const bad of bads) {
    assert.equal(isValidDiscoveryRow(bad), false, `must reject ${JSON.stringify(bad)}`);
  }
});

test("CRITICAL: rejects non-numeric-string ids", () => {
  const base = {
    chainId: 968,
    contractAddress: ADDRESS_A,
    buyer: ADDRESS_A,
    seller: ADDRESS_B,
    arbiter: ADDRESS_C,
  };
  for (const id of ["", "abc", "1.5", "-1", "0x1", " 1", "1 ", null, 1, undefined]) {
    assert.equal(isValidDiscoveryRow({ ...base, id }), false, `id=${JSON.stringify(id)} must be rejected`);
  }
  // Leading zeros are still a valid decimal string.
  assert.equal(isValidDiscoveryRow({ ...base, id: "007" }), true);
});

test("CRITICAL: rejects discovery rows outside the configured chain and contract", () => {
  const row = {
    chainId: 968,
    contractAddress: ADDRESS_A,
    id: "1",
    buyer: ADDRESS_A,
    seller: ADDRESS_B,
    arbiter: ADDRESS_C,
  };

  assert.equal(isDiscoveryRowForScope(row, 968, ADDRESS_A), true);
  assert.equal(isDiscoveryRowForScope({ ...row, chainId: 677 }, 968, ADDRESS_A), false);
  assert.equal(
    isDiscoveryRowForScope({ ...row, contractAddress: ADDRESS_B }, 968, ADDRESS_A),
    false,
  );
  assert.equal(isDiscoveryRowForScope({ ...row, contractAddress: undefined }, 968, ADDRESS_A), false);
});

test("rejects non-objects", () => {
  for (const bad of [null, undefined, 0, "", "x", [], true]) {
    assert.equal(isValidDiscoveryRow(bad), false);
  }
});

// ── event rows ────────────────────────────────────────────────────────────────

const validEvent = {
  chainId: 968,
  contractAddress: ADDRESS_A,
  transactionHash: HASH,
  blockHash: HASH,
  blockNumber: "26178651",
  logIndex: 0,
  name: "Funded",
  args: { id: "0" },
};

test("accepts a well-formed event row", () => {
  assert.equal(isValidEventRow(validEvent), true);
});

test("CRITICAL: rejects a missing contractAddress instead of throwing on toLowerCase", () => {
  assert.equal(isValidEventRow({ ...validEvent, contractAddress: undefined }), false);
  assert.equal(isValidEventRow({ ...validEvent, contractAddress: null }), false);
  assert.equal(isValidEventRow({ ...validEvent, contractAddress: "0xzz" }), false);
});

test("CRITICAL: rejects a malformed blockNumber instead of throwing on BigInt", () => {
  for (const blockNumber of ["", "abc", "0x3c8", "-1", "1.5", null, 26178651, undefined]) {
    assert.equal(
      isValidEventRow({ ...validEvent, blockNumber }),
      false,
      `blockNumber=${JSON.stringify(blockNumber)} must be rejected`,
    );
  }
});

test("rejects rows from another chain or a malformed identity", () => {
  // Chain/contract mismatch is handled by the adapter's own filter; validation
  // only has to prove the fields are safe to read and compare.
  assert.equal(isValidEventRow({ ...validEvent, chainId: 3946 }), true, "valid shape, different chain");
  assert.equal(isValidEventRow({ ...validEvent, chainId: 0 }), false, "chainId must be positive");
  assert.equal(isValidEventRow({ ...validEvent, chainId: -1 }), false);
  assert.equal(isValidEventRow({ ...validEvent, chainId: 1.5 }), false);
  assert.equal(isValidEventRow({ ...validEvent, chainId: "968" }), false, "string chainId rejected");
  assert.equal(isValidEventRow({ ...validEvent, chainId: Number.MAX_SAFE_INTEGER + 2 }), false);

  assert.equal(isValidEventRow({ ...validEvent, blockHash: "0xdead" }), false, "short block hash");
  assert.equal(isValidEventRow({ ...validEvent, transactionHash: 123 }), false);
  assert.equal(isValidEventRow({ ...validEvent, logIndex: -1 }), false);
  assert.equal(isValidEventRow({ ...validEvent, logIndex: 1.5 }), false);
  assert.equal(isValidEventRow({ ...validEvent, name: "" }), false);
  assert.equal(isValidEventRow({ ...validEvent, args: null }), false);
});

test("every field the event mapper reads is covered by validation", () => {
  // Guards against the validator and the mapper drifting apart: remove any one
  // field the mapper touches and the row must be rejected.
  const fieldsRead = [
    "chainId",
    "contractAddress",
    "transactionHash",
    "logIndex",
    "blockNumber",
    "blockHash",
    "name",
    "args",
  ];
  for (const field of fieldsRead) {
    const broken: Record<string, unknown> = { ...validEvent };
    delete broken[field];
    assert.equal(isValidEventRow(broken), false, `missing ${field} must be rejected`);
  }
});

// ── deduplication ───────────────────────────────────────────────────────────
//
// Both adapters validate rows, but only the log-scan adapter was idempotent: an
// HTTP indexer that repeated a row surfaced duplicate ActivityTimeline entries
// (React `key={event.id}` collision) and duplicate dashboard rows. These assert
// the shared helpers that http.ts now applies to both result paths.

const eventRecord = (overrides: Record<string, unknown> = {}) => {
  const base = {
    chainId: 968,
    contractAddress: ADDRESS_A,
    transactionHash: HASH,
    logIndex: 0,
    ...overrides,
  };
  return {
    ...base,
    id: `${base.chainId}:${String(base.contractAddress).toLowerCase()}:${String(base.transactionHash).toLowerCase()}:${base.logIndex}`,
    blockNumber: 100n,
    blockHash: HASH,
    name: "Funded",
    args: { id: "7" },
  };
};

test("CRITICAL: dedupeEvents collapses rows that share a canonical identity", () => {
  const deduped = dedupeEvents([eventRecord(), eventRecord()]);
  assert.equal(deduped.length, 1, "two identical events must collapse to one");
});

test("dedupeEvents keeps genuinely distinct events and preserves order", () => {
  const first = eventRecord({ logIndex: 0 });
  const second = eventRecord({ logIndex: 1 });
  const deduped = dedupeEvents([first, second, eventRecord({ logIndex: 0 })]);
  assert.deepEqual(
    deduped.map((e: { logIndex: number }) => e.logIndex),
    [0, 1],
    "distinct logIndex rows are kept, duplicate dropped, order preserved",
  );
});

test("CRITICAL: dedupeDiscoveries collapses repeated agreement ids", () => {
  const row = { id: 7n, buyer: ADDRESS_A, seller: ADDRESS_B, arbiter: ADDRESS_C };
  const deduped = dedupeDiscoveries([row, { ...row }]);
  assert.equal(deduped.length, 1, "the same agreement id must not appear twice");
});

test("dedupeDiscoveries keeps distinct ids and preserves order", () => {
  const mk = (id: bigint) => ({ id, buyer: ADDRESS_A, seller: ADDRESS_B, arbiter: ADDRESS_C });
  const deduped = dedupeDiscoveries([mk(9n), mk(7n), mk(9n)]);
  assert.deepEqual(
    deduped.map((d: { id: bigint }) => d.id),
    [9n, 7n],
  );
});
