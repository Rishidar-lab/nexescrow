/**
 * NexEscrow E2E Smoke Test — Nexus Testnet
 * Tests: create → fund → release → verify reputation
 */
import { ethers } from "ethers";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const RPC_URL = process.env.NEXUS_TESTNET_RPC_URL ?? "https://testnet.explorer.nexus.xyz/api/eth-rpc";
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const CHAIN_ID = parseInt(process.env.CHAIN_ID ?? "3945");

const ESCROW_ADDRESS = "0x4B026F5475502507800ffC95B1bF464487C13dBe";
const REGISTRY_ADDRESS = "0x57832D20f406AE9d787EB46ABA214CF0D0aA2420";

const GAS_PRICE = ethers.parseUnits("1", "gwei");

function loadArtifact(contractName) {
  const file = path.join(__dirname, "..", "artifacts", "contracts", `${contractName}.sol`, `${contractName}.json`);
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

function assert(condition, message) {
  if (!condition) {
    console.error(`  ❌ ASSERTION FAILED: ${message}`);
    process.exit(1);
  }
  console.log(`  ✅ ${message}`);
}

async function main() {
  console.log("\n╔══════════════════════════════════════════╗");
  console.log("║     NexEscrow E2E Smoke Test              ║");
  console.log("╚══════════════════════════════════════════╝\n");

  const provider = new ethers.JsonRpcProvider(RPC_URL, { chainId: CHAIN_ID, name: "nexus_testnet" });
  const deployer = new ethers.Wallet(PRIVATE_KEY, provider);

  // Use a fresh random payee (no funds needed, just receives)
  const payee = ethers.Wallet.createRandom().connect(provider);
  const arbiter = ethers.Wallet.createRandom().connect(provider);

  const blockNum = await provider.getBlockNumber();
  const balance = await provider.getBalance(deployer.address);
  console.log(`Block:    ${blockNum}`);
  console.log(`Deployer: ${deployer.address}`);
  console.log(`Balance:  ${ethers.formatEther(balance)} NEX`);
  console.log(`Payee:    ${payee.address}`);
  console.log(`Arbiter:  ${arbiter.address}\n`);

  const escrowArtifact = loadArtifact("Escrow");
  const regArtifact = loadArtifact("ReputationRegistry");

  const escrow = new ethers.Contract(ESCROW_ADDRESS, escrowArtifact.abi, deployer);
  const registry = new ethers.Contract(REGISTRY_ADDRESS, regArtifact.abi, deployer);

  // ─── Step 1: Verify wiring ─────────────────────────────────────────────────
  console.log("Step 1: Verify contract wiring...");
  const registeredEscrow = await registry.escrowContract();
  assert(registeredEscrow.toLowerCase() === ESCROW_ADDRESS.toLowerCase(),
    `ReputationRegistry.escrowContract = ${registeredEscrow}`);

  const regInEscrow = await escrow.reputationRegistry();
  assert(regInEscrow.toLowerCase() === REGISTRY_ADDRESS.toLowerCase(),
    `Escrow.reputationRegistry = ${regInEscrow}`);

  // ─── Step 2: Create escrow ─────────────────────────────────────────────────
  console.log("\nStep 2: Create escrow...");
  const latestBlock = await provider.getBlock("latest");
  const deadline = latestBlock.timestamp + 3600;
  const amount = ethers.parseEther("0.001"); // 0.001 NEX

  // Get the current nextEscrowId so we know which ID will be created
  const nextId = await escrow.nextEscrowId();
  const escrowId = nextId;
  console.log(`  Using escrow ID: ${escrowId}`);

  const createTx = await escrow.createEscrow(payee.address, arbiter.address, deadline, {
    gasLimit: 200_000n,
    gasPrice: GAS_PRICE,
  });
  console.log(`  Tx: ${createTx.hash}`);
  const createReceipt = await createTx.wait();
  assert(createReceipt.status === 1, `createEscrow confirmed at block ${createReceipt.blockNumber}`);

  const escrowInfo = await escrow.escrows(escrowId);
  assert(escrowInfo.payer.toLowerCase() === deployer.address.toLowerCase(), "payer is deployer");
  assert(escrowInfo.payee.toLowerCase() === payee.address.toLowerCase(), "payee is correct");
  assert(escrowInfo.state === 0n, "state is Open (0)");

  // ─── Step 3: Fund escrow ───────────────────────────────────────────────────
  console.log("\nStep 3: Fund escrow (0.001 NEX)...");
  const fundTx = await escrow.fund(escrowId, {
    value: amount,
    gasLimit: 100_000n,
    gasPrice: GAS_PRICE,
  });
  console.log(`  Tx: ${fundTx.hash}`);
  const fundReceipt = await fundTx.wait();
  assert(fundReceipt.status === 1, `fund confirmed at block ${fundReceipt.blockNumber}`);

  const fundedInfo = await escrow.escrows(escrowId);
  assert(fundedInfo.state === 1n, "state is Funded (1)");
  assert(fundedInfo.amount === amount, `amount = ${ethers.formatEther(fundedInfo.amount)} NEX`);

  // ─── Step 4: Release escrow ────────────────────────────────────────────────
  console.log("\nStep 4: Release escrow to payee...");
  // Note: blockscout RPC returns error for zero-balance addresses, so we
  // verify the payee received funds by checking the tx was successful
  // and the escrow state changed to Released.

  const releaseTx = await escrow.release(escrowId, {
    gasLimit: 100_000n,
    gasPrice: GAS_PRICE,
  });
  console.log(`  Tx: ${releaseTx.hash}`);
  const releaseReceipt = await releaseTx.wait();
  assert(releaseReceipt.status === 1, `release confirmed at block ${releaseReceipt.blockNumber}`);

  const releasedInfo = await escrow.escrows(escrowId);
  assert(releasedInfo.state === 2n, "state is Released (2)");

  // Verify payee balance via blockscout v2 API instead
  const payeeApiResp = await fetch(`https://testnet.explorer.nexus.xyz/api/v2/addresses/${payee.address}`);
  const payeeData = await payeeApiResp.json();
  const payeeBalance = BigInt(payeeData.coin_balance ?? "0");
  assert(payeeBalance === amount,
    `payee received ${ethers.formatEther(payeeBalance)} NEX (via explorer API)`);

  // ─── Step 5: Verify reputation ─────────────────────────────────────────────
  console.log("\nStep 5: Verify reputation records...");
  const payerRep = await registry.reputationOf(deployer.address);
  assert(payerRep.count === 1n, `payer settledCount = ${payerRep.count}`);
  assert(payerRep.volume === amount, `payer settledVolume = ${ethers.formatEther(payerRep.volume)} NEX`);

  const payeeRep = await registry.reputationOf(payee.address);
  assert(payeeRep.count === 1n, `payee settledCount = ${payeeRep.count}`);
  assert(payeeRep.volume === amount, `payee settledVolume = ${ethers.formatEther(payeeRep.volume)} NEX`);

  const participantCount = await registry.participantCount();
  assert(participantCount === 2n, `participantCount = ${participantCount}`);

  // ─── Summary ───────────────────────────────────────────────────────────────
  console.log("\n╔══════════════════════════════════════════╗");
  console.log("║   ALL SMOKE TESTS PASSED ✅               ║");
  console.log("╚══════════════════════════════════════════╝");
  console.log(`\nExplorer links:`);
  console.log(`  ReputationRegistry: https://testnet.explorer.nexus.xyz/address/${REGISTRY_ADDRESS}`);
  console.log(`  Escrow:             https://testnet.explorer.nexus.xyz/address/${ESCROW_ADDRESS}`);
  console.log(`  Create tx:          https://testnet.explorer.nexus.xyz/tx/${createTx.hash}`);
  console.log(`  Fund tx:            https://testnet.explorer.nexus.xyz/tx/${fundTx.hash}`);
  console.log(`  Release tx:         https://testnet.explorer.nexus.xyz/tx/${releaseTx.hash}`);
}

main().catch((err) => {
  console.error("\n❌ SMOKE TEST FAILED:", err.message);
  process.exit(1);
});
