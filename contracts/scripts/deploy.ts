import { network } from "hardhat";
import fs from "fs";
import path from "path";

async function main() {
  const { ethers } = await network.create();

  const [deployer] = await ethers.getSigners();
  const networkName = process.env.HARDHAT_NETWORK ?? "unknown";

  console.log("\n========================================");
  console.log(`Deploying NexEscrow to: ${networkName}`);
  console.log(`Deployer address:       ${deployer.address}`);
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log(`Deployer balance:       ${ethers.formatEther(balance)} NEX`);
  console.log("========================================\n");

  // 1. Deploy ReputationRegistry
  console.log("Deploying ReputationRegistry...");
  const ReputationRegistry = await ethers.getContractFactory("ReputationRegistry");
  const reputationRegistry = await ReputationRegistry.deploy();
  await reputationRegistry.waitForDeployment();
  const regAddress = await reputationRegistry.getAddress();
  const regTx = reputationRegistry.deploymentTransaction();
  console.log(`  ReputationRegistry deployed at: ${regAddress}`);
  console.log(`  Tx hash: ${regTx?.hash}`);

  // 2. Deploy Escrow
  console.log("\nDeploying Escrow...");
  const Escrow = await ethers.getContractFactory("Escrow");
  const escrow = await Escrow.deploy(regAddress);
  await escrow.waitForDeployment();
  const escrowAddress = await escrow.getAddress();
  const escrowTx = escrow.deploymentTransaction();
  console.log(`  Escrow deployed at: ${escrowAddress}`);
  console.log(`  Tx hash: ${escrowTx?.hash}`);

  // 3. Wire: set Escrow contract in ReputationRegistry
  console.log("\nWiring: setEscrowContract...");
  const wireTx = await reputationRegistry.setEscrowContract(escrowAddress);
  await wireTx.wait();
  console.log(`  Done. Tx: ${wireTx.hash}`);

  // 4. Get block info
  const regReceipt = await ethers.provider.getTransactionReceipt(regTx!.hash);
  const escrowReceipt = await ethers.provider.getTransactionReceipt(escrowTx!.hash);

  const output = {
    network: networkName,
    deployedAt: new Date().toISOString(),
    deployer: deployer.address,
    contracts: {
      ReputationRegistry: {
        address: regAddress,
        txHash: regTx?.hash,
        blockNumber: regReceipt?.blockNumber,
      },
      Escrow: {
        address: escrowAddress,
        txHash: escrowTx?.hash,
        blockNumber: escrowReceipt?.blockNumber,
      },
    },
  };

  // 5. Write deployment JSON
  const deploymentsDir = path.join(process.cwd(), "..", "deployments");
  fs.mkdirSync(deploymentsDir, { recursive: true });
  const outFile = path.join(deploymentsDir, `${networkName}.json`);
  fs.writeFileSync(outFile, JSON.stringify(output, null, 2));
  console.log(`\nDeployment saved to: ${outFile}`);

  console.log("\n========================================");
  console.log("DEPLOYMENT COMPLETE");
  console.log(`ReputationRegistry: ${regAddress}`);
  console.log(`Escrow:             ${escrowAddress}`);
  console.log("========================================\n");

  return output;
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
