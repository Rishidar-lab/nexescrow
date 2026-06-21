# NexEscrow Mainnet Deployment Report

## 1. Project Overview
NexEscrow is a verifiable escrow and reputation system built on the Nexus L1 network. It allows users to securely lock funds in escrow, release them to payees, and automatically builds an on-chain reputation based on settled transaction volume and count.

**GitHub Repository:** [https://github.com/Rishidar-lab/nexescrow](https://github.com/Rishidar-lab/nexescrow)
**Frontend URL:** [https://nexescrow.vercel.app/](https://nexescrow.vercel.app/)

## 2. Mainnet Deployment Details
The smart contracts were successfully deployed to the **Nexus Mainnet (Chain ID 3946)**.

* **Network:** Nexus Mainnet
* **RPC Used:** `https://mainnet.rpc.nexus.xyz`
* **Deployer Address:** `0x0326350B229f40b1Ca95324025B9434dD076FD65`

### Contract Addresses
* **ReputationRegistry:** [`0x57832D20f406AE9d787EB46ABA214CF0D0aA2420`](https://explorer.nexus.xyz/address/0x57832D20f406AE9d787EB46ABA214CF0D0aA2420)
* **Escrow:** [`0x4B026F5475502507800ffC95B1bF464487C13dBe`](https://explorer.nexus.xyz/address/0x4B026F5475502507800ffC95B1bF464487C13dBe)

## 3. Frontend Deployment
The Next.js + Wagmi + RainbowKit frontend has been configured to use the Nexus Mainnet contracts by default.
* Added `vercel.json` to configure the root directory to `frontend/`.
* The latest code pushed to the `main` branch will automatically trigger a build and deployment on Vercel.

## 4. Final Handoff
The execution of the prompt is now complete. The repository contains the Hardhat setup, the smart contracts, full tests, deployment scripts, the React/Next.js frontend, and the configuration required for Vercel auto-deployment.
