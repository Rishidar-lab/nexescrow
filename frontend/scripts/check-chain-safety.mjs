/**
 * Fail-closed chain resolution guard for CI and local checks.
 *
 * Runs the real frontend resolver (src/lib/chain.ts) and fails if the outcome is
 * unsafe. Set EXPECT_CHAIN_ID to assert the selected chain explicitly.
 *
 *   node --experimental-strip-types --no-warnings scripts/check-chain-safety.mjs
 *   NEXT_PUBLIC_CHAIN_ID=3946 EXPECT_CHAIN_ID=968 node ... (mainnet request fails closed)
 *   NEXT_PUBLIC_CHAIN_ID=3946 NEXT_PUBLIC_ALLOW_MAINNET=true EXPECT_CHAIN_ID=3946 node ...
 */
const mod = await import(new URL("../src/lib/chain.ts", import.meta.url).href);
const { selectedChainId, ALLOW_MAINNET, chainConfigWarning, supportedChains } = mod;

const mainnetIds = [3946, 677];
const problems = [];

const expected = process.env.EXPECT_CHAIN_ID ? Number(process.env.EXPECT_CHAIN_ID) : undefined;
if (expected !== undefined && selectedChainId !== expected) {
  problems.push(`expected selected chain ${expected}, got ${selectedChainId}`);
}

if (!ALLOW_MAINNET) {
  const offeredMainnets = supportedChains.filter((c) => mainnetIds.includes(c.id));
  if (offeredMainnets.length > 0) {
    problems.push(`mainnet chains offered without ALLOW_MAINNET: ${offeredMainnets.map((c) => c.id)}`);
  }
  if (mainnetIds.includes(selectedChainId)) {
    problems.push(`selected chain is mainnet ${selectedChainId} without ALLOW_MAINNET`);
  }
}

if (mainnetIds.includes(selectedChainId) && !ALLOW_MAINNET) {
  problems.push("mainnet selected without explicit opt-in");
}

const report = {
  selectedChainId,
  allowMainnet: ALLOW_MAINNET,
  offered: supportedChains.map((c) => c.id),
  warning: chainConfigWarning ?? null,
};
console.log(JSON.stringify(report));

if (problems.length > 0) {
  console.error("CHAIN SAFETY CHECK FAILED:");
  for (const p of problems) console.error(` - ${p}`);
  process.exit(1);
}
