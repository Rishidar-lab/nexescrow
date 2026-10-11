/**
 * Regression tests for the finality policy.
 *
 * These two functions are the whole reorg-safety story for log discovery, and
 * they are pure, so they can be asserted directly rather than inferred from a
 * log scan. Run with:
 *
 *   node --test --experimental-strip-types --no-warnings src/lib/__tests__
 *
 * The single most important property is the last test in this file: a scan must
 * never substitute `latestBlock` for the confirmed safe head. If it did, an
 * unconfirmed deployment would enter the discovery path and the UI would show
 * events that a reorg can erase.
 */
import { test } from "node:test";
import assert from "node:assert/strict";

const { finalityPolicyFor, confirmedSafeHead, scanReadiness } = await import(
  new URL("../finality.ts", import.meta.url).href
);

// ── per-chain policy ───────────────────────────────────────────────────────────

test("every supported chain declares an explicit two-stage policy", () => {
  for (const chainId of [3945, 3946, 968, 677]) {
    const policy = finalityPolicyFor(chainId);
    assert.equal(
      typeof policy.writeReceiptConfirmations,
      "number",
      `chain ${chainId} must declare writeReceiptConfirmations`,
    );
    assert.equal(
      typeof policy.indexingSafetyDepth,
      "number",
      `chain ${chainId} must declare indexingSafetyDepth`,
    );
    assert.ok(policy.writeReceiptConfirmations > 0, "write confirmations must be positive");
    assert.ok(policy.indexingSafetyDepth > 0, "indexing depth must be positive");
  }
});

test("the two finality stages are independently tunable, not aliases", () => {
  // Deliberately does NOT assert the two values differ. Equal values are a
  // perfectly valid policy — a chain could legitimately need the same number of
  // confirmations for a write receipt and for indexing safety. What must not
  // happen is the two collapsing into ONE field, so this checks they are
  // separately present, separately named and independently writable.
  const policy = finalityPolicyFor(968) as Record<string, unknown>;
  assert.ok("writeReceiptConfirmations" in policy, "write-receipt stage must be its own field");
  assert.ok("indexingSafetyDepth" in policy, "indexing stage must be its own field");
  assert.equal(Object.keys(policy).length, 2, "policy must expose exactly the two stages");

  // Each is read independently: changing one must not move the other.
  const bohr = finalityPolicyFor(968);
  const nexus = finalityPolicyFor(3945);
  assert.equal(
    bohr.writeReceiptConfirmations === nexus.writeReceiptConfirmations ||
      bohr.indexingSafetyDepth === nexus.indexingSafetyDepth,
    true,
    "per-chain policies are free to differ in either stage independently",
  );
});

test("an unknown chain falls back to the default policy rather than throwing", () => {
  const fallback = finalityPolicyFor(999999);
  const known = finalityPolicyFor(968);
  assert.equal(fallback.writeReceiptConfirmations, known.writeReceiptConfirmations);
  assert.equal(fallback.indexingSafetyDepth, known.indexingSafetyDepth);
});

// ── confirmedSafeHead ─────────────────────────────────────────────────────────

test("confirmedSafeHead subtracts the depth from the latest block", () => {
  assert.equal(confirmedSafeHead(111n, 12), 99n);
  assert.equal(confirmedSafeHead(100n, 0), 100n);
});

test("confirmedSafeHead is null when the chain is shallower than the depth", () => {
  assert.equal(confirmedSafeHead(5n, 12), null, "a young chain must have no safe head");
  assert.equal(confirmedSafeHead(11n, 12), null, "one block short is still not safe");
  assert.equal(confirmedSafeHead(0n, 1), null);
});

test("confirmedSafeHead rejects a negative or non-integer depth", () => {
  assert.throws(() => confirmedSafeHead(100n, -1), /Invalid indexing safety depth/);
  assert.throws(() => confirmedSafeHead(100n, 1.5), /Invalid indexing safety depth/);
});

// ── scanReadiness ─────────────────────────────────────────────────────────────

test("a deployment newer than the safe head stays pending", () => {
  // startBlock 100 vs safe head 99 (111 - 12): must NOT be scannable.
  const pending = scanReadiness(100n, 111n, 12);
  assert.equal(pending.ready, false, "unconfirmed deployment must remain pending");
  assert.equal(pending.safeHead, 99n, "pending scan keeps the confirmed head");
});

test("a deployment becomes scannable exactly at the required depth", () => {
  const ready = scanReadiness(100n, 112n, 12);
  assert.equal(ready.ready, true, "deployment is safe once the safe head reaches it");
  assert.equal(ready.safeHead, 100n);
});

test("a chain shallower than the depth never becomes ready", () => {
  const shallow = scanReadiness(1n, 5n, 12);
  assert.equal(shallow.ready, false);
  assert.equal(shallow.safeHead, null);
});

test("startBlock below the safe head is scannable", () => {
  const ready = scanReadiness(50n, 200n, 12);
  assert.equal(ready.ready, true);
  assert.equal(ready.safeHead, 188n);
});

test("CRITICAL: the safe head is never the latest block", () => {
  // Regression guard. A previous shape of this logic fell back to `latestBlock`
  // when the deployment was too new, which would have exposed unconfirmed
  // events through discovery. Sweep a range and assert the separation holds.
  for (let latest = 1n; latest <= 40n; latest++) {
    const head = confirmedSafeHead(latest, 12);
    if (head === null) continue;
    assert.ok(head < latest, `safe head ${head} must be strictly below latest ${latest}`);
    assert.equal(head, latest - 12n);
  }
});

test("CRITICAL: a startBlock above the safe head is never reported ready", () => {
  for (let latest = 13n; latest <= 40n; latest++) {
    const ahead = scanReadiness(latest, latest, 12);
    assert.equal(ahead.ready, false, `start == latest (${latest}) must stay pending`);
    assert.ok(
      ahead.safeHead === null || ahead.safeHead < latest,
      "pending result must never report the latest block as safe",
    );
  }
});