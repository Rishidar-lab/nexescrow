import { ethers } from "ethers";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const RPC_URL = "https://testnet.explorer.nexus.xyz/api/eth-rpc";
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const ESCROW_ADDRESS = "0x4B026F5475502507800ffC95B1bF464487C13dBe";
const GAS_PRICE = ethers.parseUnits("1", "gwei");
const abi = JSON.parse(fs.readFileSync(path.join(__dirname, "../artifacts/contracts/Escrow.sol/Escrow.json"))).abi;
const provider = new ethers.JsonRpcProvider(RPC_URL, { chainId: 3945, name: "nexus_testnet" });
const wallet = new ethers.Wallet(PRIVATE_KEY, provider);
const escrow = new ethers.Contract(ESCROW_ADDRESS, abi, wallet);

// Check escrow 3
const info = await escrow.escrows(3);
console.log("Escrow 3:", { payer: info.payer, payee: info.payee, state: info.state.toString(), amount: ethers.formatEther(info.amount) });

// Try to call release statically to get the revert reason
try {
  const result = await escrow.release.staticCall(3, { gasLimit: 100_000n, gasPrice: GAS_PRICE });
  console.log("Static call result:", result);
} catch (e) {
  console.log("Static call revert reason:", e.message);
  if (e.data) console.log("Revert data:", e.data);
}
