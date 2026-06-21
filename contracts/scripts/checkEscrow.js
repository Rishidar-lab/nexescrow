import { ethers } from "ethers";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const provider = new ethers.JsonRpcProvider("https://testnet.explorer.nexus.xyz/api/eth-rpc", { chainId: 3945, name: "nexus_testnet" });
const abi = JSON.parse(fs.readFileSync(path.join(__dirname, "../artifacts/contracts/Escrow.sol/Escrow.json"))).abi;
const escrow = new ethers.Contract("0x4B026F5475502507800ffC95B1bF464487C13dBe", abi, provider);
const nextId = await escrow.nextEscrowId();
console.log("nextEscrowId:", nextId.toString());
for (let i = 1; i < Number(nextId); i++) {
  const info = await escrow.escrows(i);
  console.log(`Escrow ${i}:`, { payer: info.payer, payee: info.payee, state: info.state.toString(), amount: ethers.formatEther(info.amount) });
}
