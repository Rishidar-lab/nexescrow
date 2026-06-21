import { ethers } from "ethers";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// ─── Config ───────────────────────────────────────────────────────────────────
const RPC_URL = process.env.NEXUS_TESTNET_RPC_URL ?? "https://testnet.explorer.nexus.xyz/api/eth-rpc";
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const NETWORK_NAME = process.env.NETWORK_NAME ?? "nexus_testnet";
const CHAIN_ID = parseInt(process.env.CHAIN_ID ?? "3945");

// Gas settings (manual, to bypass blockscout's broken eth_estimateGas for deployments)
const GAS_LIMIT_REGISTRY = 1_500_000n;
const GAS_LIMIT_ESCROW   = 2_000_000n;
const GAS_LIMIT_WIRE     = 100_000n;
const GAS_PRICE          = ethers.parseUnits("1", "gwei"); // 1 gwei

if (!PRIVATE_KEY) {
  console.error("PRIVATE_KEY env var is required");
  process.exit(1);
}

// ─── Load artifacts ───────────────────────────────────────────────────────────
const artifactsDir = path.join(__dirname, "..", "artifacts", "contracts");

function loadArtifact(contractName) {
  const file = path.join(artifactsDir, `${contractName}.sol`, `${contractName}.json`);
  return JSON.parse(fs.readFileSync(file, "utf8"));
}

// ─── Main ─────────────────────────────────────────────────────────────────────
async function main() {
  const provider = new ethers.JsonRpcProvider(RPC_URL, {
    chainId: CHAIN_ID,
    name: NETWORK_NAME,
  });

  const wallet = new ethers.Wallet(PRIVATE_KEY, provider);

  const balance = await provider.getBalance(wallet.address);
  const blockNum = await provider.getBlockNumber();

  console.log("\n========================================");
  console.log(`Network:          ${NETWORK_NAME} (chain ${CHAIN_ID})`);
  console.log(`RPC:              ${RPC_URL}`);
  console.log(`Block:            ${blockNum}`);
  console.log(`Deployer:         ${wallet.address}`);
  console.log(`Balance:          ${ethers.formatEther(balance)} NEX`);
  console.log("========================================\n");

  if (balance === 0n) {
    console.error("Deployer has no balance. Please fund the wallet first.");
    process.exit(1);
  }

  // 1. Deploy ReputationRegistry
  console.log("1/3  Deploying ReputationRegistry...");
  const regArtifact = loadArtifact("ReputationRegistry");
  const regFactory = new ethers.ContractFactory(regArtifact.abi, regArtifact.bytecode, wallet);
  const regContract = await regFactory.deploy({
    gasLimit: GAS_LIMIT_REGISTRY,
    gasPrice: GAS_PRICE,
  });
  const regDeployTx = regContract.deploymentTransaction();
  console.log(`     Tx hash:  ${regDeployTx.hash}`);
  const regDeployReceipt = await regContract.waitForDeployment();
  const regAddress = await regContract.getAddress();
  const regReceipt = await provider.getTransactionReceipt(regDeployTx.hash);
  console.log(`     Address:  ${regAddress}`);
  console.log(`     Block:    ${regReceipt.blockNumber}`);
  console.log(`     Gas used: ${regReceipt.gasUsed.toString()}`);

  // 2. Deploy Escrow
  console.log("\n2/3  Deploying Escrow...");
  const escrowArtifact = loadArtifact("Escrow");
  const escrowFactory = new ethers.ContractFactory(escrowArtifact.abi, escrowArtifact.bytecode, wallet);
  const escrowContract = await escrowFactory.deploy(regAddress, {
    gasLimit: GAS_LIMIT_ESCROW,
    gasPrice: GAS_PRICE,
  });
  const escrowDeployTx = escrowContract.deploymentTransaction();
  console.log(`     Tx hash:  ${escrowDeployTx.hash}`);
  await escrowContract.waitForDeployment();
  const escrowAddress = await escrowContract.getAddress();
  const escrowReceipt = await provider.getTransactionReceipt(escrowDeployTx.hash);
  console.log(`     Address:  ${escrowAddress}`);
  console.log(`     Block:    ${escrowReceipt.blockNumber}`);
  console.log(`     Gas used: ${escrowReceipt.gasUsed.toString()}`);

  // 3. Wire: setEscrowContract
  console.log("\n3/3  Wiring: ReputationRegistry.setEscrowContract...");
  const regInstance = new ethers.Contract(regAddress, regArtifact.abi, wallet);
  const wireTx = await regInstance.setEscrowContract(escrowAddress, {
    gasLimit: GAS_LIMIT_WIRE,
    gasPrice: GAS_PRICE,
  });
  console.log(`     Tx hash:  ${wireTx.hash}`);
  const wireReceipt = await wireTx.wait();
  console.log(`     Block:    ${wireReceipt.blockNumber}`);
  console.log(`     Done.`);

  // 4. Save deployment JSON
  const output = {
    network: NETWORK_NAME,
    chainId: CHAIN_ID,
    deployedAt: new Date().toISOString(),
    deployer: wallet.address,
    rpcUsed: RPC_URL,
    contracts: {
      ReputationRegistry: {
        address: regAddress,
        txHash: regDeployTx.hash,
        blockNumber: regReceipt.blockNumber,
        gasUsed: regReceipt.gasUsed.toString(),
      },
      Escrow: {
        address: escrowAddress,
        txHash: escrowDeployTx.hash,
        blockNumber: escrowReceipt.blockNumber,
        gasUsed: escrowReceipt.gasUsed.toString(),
      },
    },
  };

  const deploymentsDir = path.join(__dirname, "..", "..", "deployments");
  fs.mkdirSync(deploymentsDir, { recursive: true });
  const outFile = path.join(deploymentsDir, `${NETWORK_NAME}.json`);
  fs.writeFileSync(outFile, JSON.stringify(output, null, 2));

  console.log("\n========================================");
  console.log("DEPLOYMENT COMPLETE");
  console.log(`ReputationRegistry: ${regAddress}`);
  console.log(`Escrow:             ${escrowAddress}`);
  console.log(`Saved to:           ${outFile}`);
  console.log("========================================\n");

  return output;
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
