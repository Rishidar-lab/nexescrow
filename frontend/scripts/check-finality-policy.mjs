/**
 * Regression checks for finality-stage separation and pending deployment scans.
 *
 * Runs the same pure policy/readiness helpers used by the frontend log scanner.
 * The key regression is that a deployment newer than the confirmed safe head
 * must remain pending; it must never fall back to the latest block.
 */
const mod = await import(new URL("../src/lib/finality.ts", import.meta.url).href);
const { finalityPolicyFor, scanReadiness } = mod;

function assert(condition, message) {
  if (!condition) throw new Error(`FINALITY POLICY CHECK FAILED: ${message}`);
}

const bohr = finalityPolicyFor(968);
assert(bohr.writeReceiptConfirmations === 2, "Bohr write-receipt stage should remain explicit at 2");
assert(bohr.indexingSafetyDepth === 12, "Bohr indexing safety depth should remain explicit at 12");

// Deployment block 100 is newer than safe head 99 (111 - 12): pending.
const pending = scanReadiness(100n, 111n, 12);
assert(pending.ready === false, "deployment newer than safe head must remain pending");
assert(pending.safeHead === 99n, "pending scan must retain safe head 99, not latest 111");

// Once the required depth is reached, exactly the deployment block is safe.
const ready = scanReadiness(100n, 112n, 12);
assert(ready.ready === true, "deployment should become scannable at required depth");
assert(ready.safeHead === 100n, "ready scan should begin with confirmed head 100");

// Chains younger than the safety depth also remain pending.
const shallow = scanReadiness(1n, 5n, 12);
assert(shallow.ready === false && shallow.safeHead === null, "insufficient chain depth must remain pending");

console.log("finality policy regression checks passed");
