/**
 * Complete the E2E smoke test: release escrow 3 and verify reputation
 */
import { ethers } from "ethers";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const RPC_URL = "https://testnet.explorer.nexus.xyz/api/eth-rpc";
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const ESCROW_ADDRESS = "0x4B026F5475502507800ffC95B1bF464487C13dBe";
const REGISTRY_ADDRESS = "0x57832D20f406AE9d787EB46ABA214CF0D0aA2420";
const ESCROW_ID = 3;
const PAYEE = "0xae13FfAD6746c54C3658e836bFCb0dfDCE1E02EF";
const GAS_PRICE = ethers.parseUnits("1", "gwei");
const GAS_LIMIT = 300_000n; // Increased from 100k

function loadArtifact(name) {
  return JSON.parse(fs.readFileSync(path.join(__dirname, `../artifacts/contracts/${name}.sol/${name}.json`))).abi;
}

function assert(cond, msg) {
  if (!cond) { console.error(`  ❌ FAILED: ${msg}`); process.exit(1); }
  console.log(`  ✅ ${msg}`);
}

const provider = new ethers.JsonRpcProvider(RPC_URL, { chainId: 3945, name: "nexus_testnet" });
const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
const escrow = new ethers.Contract(ESCROW_ADDRESS, loadArtifact("Escrow"), wallet);
const registry = new ethers.Contract(REGISTRY_ADDRESS, loadArtifact("ReputationRegistry"), wallet);

console.log("\n── Releasing escrow 3 ──────────────────────────");
const releaseTx = await escrow.release(ESCROW_ID, { gasLimit: GAS_LIMIT, gasPrice: GAS_PRICE });
console.log(`  Tx: ${releaseTx.hash}`);
const receipt = await releaseTx.wait();
assert(receipt.status === 1, `release confirmed at block ${receipt.blockNumber}, gas used: ${receipt.gasUsed}`);

const info = await escrow.escrows(ESCROW_ID);
assert(info.state === 2n, "state is Released (2)");

// Verify payee balance via explorer API
await new Promise(r => setTimeout(r, 5000)); // wait for indexer
const resp = await fetch(`https://testnet.explorer.nexus.xyz/api/v2/addresses/${PAYEE}`);
const data = await resp.json();
const payeeBalance = BigInt(data.coin_balance ?? "0");
assert(payeeBalance >= ethers.parseEther("0.001"), `payee balance = ${ethers.formatEther(payeeBalance)} NEX`);

console.log("\n── Verifying reputation ────────────────────────");
const payerRep = await registry.reputationOf(wallet.address);
console.log(`  Payer settledCount:  ${payerRep.count}`);
console.log(`  Payer settledVolume: ${ethers.formatEther(payerRep.volume)} NEX`);
assert(payerRep.count >= 1n, `payer settledCount >= 1`);

const payeeRep = await registry.reputationOf(PAYEE);
console.log(`  Payee settledCount:  ${payeeRep.count}`);
console.log(`  Payee settledVolume: ${ethers.formatEther(payeeRep.volume)} NEX`);
assert(payeeRep.count >= 1n, `payee settledCount >= 1`);

const participantCount = await registry.participantCount();
assert(participantCount >= 2n, `participantCount >= 2 (got ${participantCount})`);

console.log("\n╔══════════════════════════════════════════╗");
console.log("║   ALL SMOKE TESTS PASSED ✅               ║");
console.log("╚══════════════════════════════════════════╝");
console.log(`\nExplorer links:`);
console.log(`  ReputationRegistry: https://testnet.explorer.nexus.xyz/address/${REGISTRY_ADDRESS}`);
console.log(`  Escrow:             https://testnet.explorer.nexus.xyz/address/${ESCROW_ADDRESS}`);
console.log(`  Release tx:         https://testnet.explorer.nexus.xyz/tx/${releaseTx.hash}`);
