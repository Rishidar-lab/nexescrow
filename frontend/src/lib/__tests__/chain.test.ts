/**
 * Regression tests for the fail-closed chain resolver.
 *
 * `src/lib/chain.ts` reads `process.env` at module load, so its resolution
 * cannot be exercised in-process — the values would be frozen at import. The
 * honest way to test it is to run the real module in a child process with a
 * given environment and read what it actually decided, which is exactly what
 * these tests do. No source refactor, no mocking, no reimplementation.
 *
 * Run with:
 *   node --test --experimental-strip-types --no-warnings src/lib/__tests__
 */
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const CHAIN_MODULE = new URL("../chain.ts", import.meta.url).href;
const chainModulePath = fileURLToPath(CHAIN_MODULE);

interface Resolution {
  selectedChainId: number;
  allowMainnet: boolean;
  warning: string | null;
  offered: number[];
}

/** Run the real resolver in a child process with the given environment. */
function resolve(env: Record<string, string | undefined>): Resolution {
  const script =
    `const m = await import(${JSON.stringify(chainModulePath)});` +
    `process.stdout.write(JSON.stringify({` +
    `selectedChainId: m.selectedChainId,` +
    `allowMainnet: m.ALLOW_MAINNET,` +
    `warning: m.chainConfigWarning ?? null,` +
    `offered: m.supportedChains.map((c) => c.id),` +
    `}));`;

  const out = execFileSync(process.execPath, ["--experimental-strip-types", "--no-warnings", "--input-type=module", "-e", script], {
    env: {
      PATH: process.env.PATH,
      HOME: process.env.HOME,
      NODE_ENV: process.env.NODE_ENV ?? "test",
      // Start from a clean slate: no inherited chain configuration.
      NEXT_PUBLIC_CHAIN_ID: "",
      NEXT_PUBLIC_DEFAULT_CHAIN_ID: "",
      NEXT_PUBLIC_ALLOW_MAINNET: "",
      ...env,
    },
    encoding: "utf8",
  });
  return JSON.parse(out) as Resolution;
}

const BOT_TESTNET = 968;
const NEXUS_TESTNET = 3945;
const NEXUS_MAINNET = 3946;
const BOT_MAINNET = 677;

// ── the default is always a testnet ───────────────────────────────────────────

test("with no configuration at all, the build selects BOT Bohr testnet", () => {
  const r = resolve({});
  assert.equal(r.selectedChainId, BOT_TESTNET);
  assert.equal(r.allowMainnet, false);
  assert.equal(r.warning, null, "the default needs no warning; it is simply the default");
});

test("mainnet chains are never offered to the wallet without opt-in", () => {
  const r = resolve({});
  assert.equal(r.offered.includes(NEXUS_MAINNET), false);
  assert.equal(r.offered.includes(BOT_MAINNET), false);
  assert.deepEqual(r.offered.sort(), [NEXUS_TESTNET, BOT_TESTNET].sort());
});

// ── mainnet requests fail closed ──────────────────────────────────────────────

test("requesting Nexus mainnet without opt-in fails closed to testnet", () => {
  const r = resolve({ NEXT_PUBLIC_CHAIN_ID: String(NEXUS_MAINNET) });
  assert.equal(r.selectedChainId, BOT_TESTNET, "must not select mainnet");
  assert.match(r.warning ?? "", /failed closed to BOT Bohr testnet/);
});

test("requesting BOT mainnet without opt-in fails closed to testnet", () => {
  const r = resolve({ NEXT_PUBLIC_CHAIN_ID: String(BOT_MAINNET) });
  assert.equal(r.selectedChainId, BOT_TESTNET);
  assert.match(r.warning ?? "", /failed closed/);
});

test("CRITICAL: mainnet opt-in is not granted by a truthy-looking value", () => {
  // `ALLOW_MAINNET` is compared to the exact string "true". Anything else — even
  // "TRUE", "1" or "yes" — must not unlock real-money chains.
  for (const value of ["TRUE", "1", "yes", "on", "True"]) {
    const r = resolve({ NEXT_PUBLIC_CHAIN_ID: String(NEXUS_MAINNET), NEXT_PUBLIC_ALLOW_MAINNET: value });
    assert.equal(r.allowMainnet, false, `"${value}" must not enable mainnet`);
    assert.equal(r.selectedChainId, BOT_TESTNET, `"${value}" must not select mainnet`);
    assert.equal(r.offered.includes(NEXUS_MAINNET), false, `"${value}" must not offer mainnet`);
  }
});

test("explicit opt-in does select and offer mainnet", () => {
  const r = resolve({ NEXT_PUBLIC_CHAIN_ID: String(NEXUS_MAINNET), NEXT_PUBLIC_ALLOW_MAINNET: "true" });
  assert.equal(r.allowMainnet, true);
  assert.equal(r.selectedChainId, NEXUS_MAINNET);
  assert.equal(r.warning, null);
  assert.equal(r.offered.includes(NEXUS_MAINNET), true);
});

// ── unknown and malformed input fails closed ──────────────────────────────────

test("an unknown chain id fails closed to testnet", () => {
  const r = resolve({ NEXT_PUBLIC_CHAIN_ID: "1" });
  assert.equal(r.selectedChainId, BOT_TESTNET);
  assert.match(r.warning ?? "", /Unknown chain id/);
});

test("a non-numeric chain id fails closed rather than being coerced", () => {
  for (const value of ["", "abc", "968; rm -rf /", "0x3c8", "-1"]) {
    const r = resolve({ NEXT_PUBLIC_CHAIN_ID: value });
    assert.equal(r.selectedChainId, BOT_TESTNET, `"${value}" must fail closed`);
    assert.equal(r.allowMainnet, false);
  }
});

test("an explicit testnet request is honoured", () => {
  const r = resolve({ NEXT_PUBLIC_CHAIN_ID: String(NEXUS_TESTNET) });
  assert.equal(r.selectedChainId, NEXUS_TESTNET);
  assert.equal(r.warning, null);
});

test("a configured default is used when no explicit request is present", () => {
  const r = resolve({ NEXT_PUBLIC_DEFAULT_CHAIN_ID: String(NEXUS_TESTNET) });
  assert.equal(r.selectedChainId, NEXUS_TESTNET);
});

test("a mainnet DEFAULT also fails closed without opt-in", () => {
  const r = resolve({ NEXT_PUBLIC_DEFAULT_CHAIN_ID: String(BOT_MAINNET) });
  assert.equal(r.selectedChainId, BOT_TESTNET);
  assert.match(r.warning ?? "", /failed closed/);
});

// ── pure helpers ──────────────────────────────────────────────────────────────

test("mainnet / testnet classification covers every known chain", async () => {
  const m = await import(new URL("../chain.ts", import.meta.url).href);
  assert.equal(m.isMainnetChain(NEXUS_MAINNET), true);
  assert.equal(m.isMainnetChain(BOT_MAINNET), true);
  assert.equal(m.isMainnetChain(BOT_TESTNET), false);
  assert.equal(m.isMainnetChain(NEXUS_TESTNET), false);

  assert.equal(m.isTestnetChain(BOT_TESTNET), true);
  assert.equal(m.isTestnetChain(NEXUS_TESTNET), true);
  assert.equal(m.isTestnetChain(BOT_MAINNET), false);

  assert.equal(m.chainStatusLabel(NEXUS_MAINNET), "MAINNET");
  assert.equal(m.chainStatusLabel(BOT_TESTNET), "TESTNET");
  assert.equal(m.chainStatusLabel(999999), "UNKNOWN");
});

test("chainById rejects an unsupported chain instead of returning a default", async () => {
  const m = await import(new URL("../chain.ts", import.meta.url).href);
  assert.throws(() => m.chainById(999999), /Unsupported chain id/);
  assert.equal(m.chainById(BOT_TESTNET).id, BOT_TESTNET);
});