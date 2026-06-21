import { ethers } from "ethers";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const provider = new ethers.JsonRpcProvider("https://testnet.explorer.nexus.xyz/api/eth-rpc", { chainId: 3945, name: "nexus_testnet" });
const abi = JSON.parse(fs.readFileSync(path.join(__dirname, "../artifacts/contracts/ReputationRegistry.sol/ReputationRegistry.json"))).abi;
const registry = new ethers.Contract("0x57832D20f406AE9d787EB46ABA214CF0D0aA2420", abi, provider);

const DEPLOYER = "0x0326350B229f40b1Ca95324025B9434dD076FD65";
const PAYEE = "0xae13FfAD6746c54C3658e836bFCb0dfDCE1E02EF";

const payerRep = await registry.reputationOf(DEPLOYER);
console.log("Payer reputation:");
console.log("  settledCount:", payerRep.count.toString());
console.log("  settledVolume:", ethers.formatEther(payerRep.volume), "NEX");

const payeeRep = await registry.reputationOf(PAYEE);
console.log("Payee reputation:");
console.log("  settledCount:", payeeRep.count.toString());
console.log("  settledVolume:", ethers.formatEther(payeeRep.volume), "NEX");

const participantCount = await registry.participantCount();
console.log("Total participants:", participantCount.toString());

// Leaderboard
const [addrs, counts, volumes] = await registry.leaderboard(0, 10);
console.log("\nLeaderboard:");
for (let i = 0; i < addrs.length; i++) {
  console.log(`  ${addrs[i]}: count=${counts[i]}, volume=${ethers.formatEther(volumes[i])} NEX`);
}
