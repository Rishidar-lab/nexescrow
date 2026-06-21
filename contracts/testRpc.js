import { ethers } from "ethers";
const BLOCKSCOUT_RPC = "https://nexus.testnet.blockscout.com/api/eth-rpc";
try {
  const provider = new ethers.JsonRpcProvider(BLOCKSCOUT_RPC, {
    chainId: 3945,
    name: "nexus_testnet"
  });
  const blockNum = await provider.getBlockNumber();
  console.log("Block number:", blockNum);
  const balance = await provider.getBalance("0x0326350B229f40b1Ca95324025B9434dD076FD65");
  console.log("Balance:", ethers.formatEther(balance), "NEX");
} catch(e) {
  console.log("Error:", e.message);
}
