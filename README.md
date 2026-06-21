# NexEscrow

**Verifiable escrow and on-chain reputation system built on Nexus L1.**

NexEscrow lets any two parties transact trustlessly — the payer locks funds in a smart contract, the payee delivers, and the payer releases. Every settled escrow automatically increments both parties' on-chain reputation score. An optional arbiter can be designated at creation time for dispute resolution.

[![CI](https://github.com/Rishidar-lab/nexescrow/actions/workflows/ci.yml/badge.svg)](https://github.com/Rishidar-lab/nexescrow/actions)
[![Live on Vercel](https://img.shields.io/badge/frontend-nexescrow.vercel.app-blue)](https://nexescrow.vercel.app)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## Live Deployments

| Environment | Network | Chain ID | Explorer |
|---|---|---|---|
| **Testnet** | Nexus Testnet | 3945 | [testnet.explorer.nexus.xyz](https://testnet.explorer.nexus.xyz) |
| **Mainnet** | Nexus Mainnet | 3946 | [explorer.nexus.xyz](https://explorer.nexus.xyz) |

### Contract Addresses

| Contract | Testnet | Mainnet |
|---|---|---|
| `ReputationRegistry` | [`0x57832D20f406AE9d787EB46ABA214CF0D0aA2420`](https://testnet.explorer.nexus.xyz/address/0x57832D20f406AE9d787EB46ABA214CF0D0aA2420) | [`0x57832D20f406AE9d787EB46ABA214CF0D0aA2420`](https://explorer.nexus.xyz/address/0x57832D20f406AE9d787EB46ABA214CF0D0aA2420) |
| `Escrow` | [`0x4B026F5475502507800ffC95B1bF464487C13dBe`](https://testnet.explorer.nexus.xyz/address/0x4B026F5475502507800ffC95B1bF464487C13dBe) | [`0x4B026F5475502507800ffC95B1bF464487C13dBe`](https://explorer.nexus.xyz/address/0x4B026F5475502507800ffC95B1bF464487C13dBe) |

### Frontend

> **[https://nexescrow.vercel.app](https://nexescrow.vercel.app)**

---

## Repository Structure

```
nexescrow/
├── contracts/               # Hardhat project — Solidity contracts, tests, scripts
│   ├── contracts/
│   │   ├── Escrow.sol               # Core escrow logic
│   │   └── ReputationRegistry.sol   # On-chain reputation tracking
│   ├── scripts/
│   │   ├── deploy.ts                # Hardhat deploy script
│   │   ├── deployDirect.js          # Standalone ethers deploy (used for live deploys)
│   │   └── smokeTest.js             # E2E smoke test against live testnet
│   ├── test/
│   │   └── Escrow.ts                # 15-test Hardhat test suite
│   ├── hardhat.config.ts
│   └── .env.example
├── frontend/                # Next.js 14 App Router frontend
│   ├── src/
│   │   ├── app/
│   │   │   ├── page.tsx             # Main dApp UI
│   │   │   ├── providers.tsx        # Wagmi + RainbowKit providers
│   │   │   └── layout.tsx
│   │   └── contracts/
│   │       └── index.ts             # Auto-generated ABIs + addresses
│   └── package.json
├── deployments/             # Deployment receipts (JSON)
│   ├── nexus_testnet.json
│   └── nexus_mainnet.json
└── copyArtifacts.js         # Copies ABIs + addresses to frontend
```

---

## Smart Contracts

### `Escrow.sol`

The core contract managing the full escrow lifecycle.

| Function | Access | Description |
|---|---|---|
| `createEscrow(payee, arbiter, deadline)` | Anyone | Creates a new escrow and returns its ID |
| `fund(escrowId)` | Payer | Funds the escrow with native NEX (payable) |
| `release(escrowId)` | Payer or Arbiter | Releases funds to payee and records reputation |
| `refund(escrowId)` | Payer (after deadline) | Refunds payer if deadline has passed |
| `dispute(escrowId)` | Payer or Payee | Raises a dispute flag for arbiter review |

**Security:** `ReentrancyGuard`, custom errors, `address(0)` validation, state-machine enforcement.

### `ReputationRegistry.sol`

Tracks on-chain reputation for every address that participates in a settled escrow.

| Function | Access | Description |
|---|---|---|
| `recordSettlement(payer, payee, amount)` | Escrow contract only | Increments `settledCount` and `settledVolume` for both parties |
| `reputationOf(addr)` | Public view | Returns `(settledCount, settledVolume)` for an address |
| `leaderboard(n)` | Public view | Returns top-N addresses by settled volume |
| `setEscrowContract(addr)` | Owner only | Wires the registry to the Escrow contract |

---

## Getting Started

### Prerequisites

- Node.js ≥ 18
- npm ≥ 9
- A wallet with NEX (testnet faucet: [faucet.nexus.xyz](https://faucet.nexus.xyz))

### 1. Clone the Repository

```bash
git clone https://github.com/Rishidar-lab/nexescrow.git
cd nexescrow
```

### 2. Set Up Contracts

```bash
cd contracts
npm install

# Copy the example env file and fill in your private key
cp .env.example .env
```

Edit `.env`:

```env
PRIVATE_KEY=0xYOUR_DEPLOYER_PRIVATE_KEY
NEXUS_TESTNET_RPC_URL=https://testnet.explorer.nexus.xyz/api/eth-rpc
NEXUS_MAINNET_RPC_URL=https://mainnet.rpc.nexus.xyz
```

### 3. Compile Contracts

```bash
npx hardhat compile
```

### 4. Run Tests

```bash
npx hardhat test
```

All 15 tests should pass:

```
  Escrow
    Deployment
      ✔ Should set the right owner
      ✔ Should wire ReputationRegistry correctly
    createEscrow
      ✔ Should create an escrow with correct fields
      ✔ Should revert if payee is zero address
      ✔ Should revert if deadline is in the past
    fund
      ✔ Should fund an escrow
      ✔ Should revert if not the payer
      ✔ Should revert if already funded
    release
      ✔ Should release funds to payee
      ✔ Should update reputation on release
      ✔ Should revert if not payer or arbiter
    refund
      ✔ Should refund after deadline
      ✔ Should revert before deadline
    dispute
      ✔ Should allow payer to raise dispute
      ✔ Should revert if already disputed

  15 passing
```

### 5. Deploy to Testnet

```bash
# Make sure your .env has PRIVATE_KEY and NEXUS_TESTNET_RPC_URL set
NEXUS_TESTNET_RPC_URL=https://testnet.explorer.nexus.xyz/api/eth-rpc \
PRIVATE_KEY=0xYOUR_KEY \
node scripts/deployDirect.js
```

Deployment addresses will be saved to `../deployments/nexus_testnet.json`.

### 6. Run the E2E Smoke Test

```bash
NEXUS_TESTNET_RPC_URL=https://testnet.explorer.nexus.xyz/api/eth-rpc \
PRIVATE_KEY=0xYOUR_KEY \
node scripts/smokeTest.js
```

This will create, fund, and release an escrow on the live testnet and verify reputation records on-chain.

### 7. Deploy to Mainnet

> **Only proceed after testnet validation is complete and smoke test passes.**

```bash
NEXUS_TESTNET_RPC_URL=https://mainnet.rpc.nexus.xyz \
PRIVATE_KEY=0xYOUR_KEY \
CHAIN_ID=3946 \
node scripts/deployDirect.js
```

---

## Running the Frontend

### Development

```bash
cd frontend
npm install --legacy-peer-deps
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

### Production Build

```bash
cd frontend
npm run build
npm start
```

### Sync Contract Addresses to Frontend

After any new deployment, run this from the repo root to regenerate `frontend/src/contracts/index.ts`:

```bash
node copyArtifacts.js
```

---

## Adding Nexus to MetaMask

The frontend automatically prompts `wallet_addEthereumChain` when you connect. To add manually:

**Nexus Mainnet**

| Field | Value |
|---|---|
| Network Name | Nexus Mainnet |
| RPC URL | `https://mainnet.rpc.nexus.xyz` |
| Chain ID | `3946` |
| Currency Symbol | `NEX` |
| Block Explorer | `https://explorer.nexus.xyz` |

**Nexus Testnet**

| Field | Value |
|---|---|
| Network Name | Nexus Testnet |
| RPC URL | `https://testnet.explorer.nexus.xyz/api/eth-rpc` |
| Chain ID | `3945` |
| Currency Symbol | `NEX` |
| Block Explorer | `https://testnet.explorer.nexus.xyz` |

---

## CI / CD

GitHub Actions runs on every push to `main` and every pull request:

- **Compile** — `npx hardhat compile`
- **Test** — `npx hardhat test`

Vercel auto-deploys the frontend on every push to `main` (root directory: `frontend`, framework: Next.js).

---

## Tech Stack

| Layer | Technology |
|---|---|
| Smart Contracts | Solidity `^0.8.24`, OpenZeppelin 5.x |
| Development / Testing | Hardhat 3, ethers.js v6, Mocha, Chai |
| Frontend Framework | Next.js 14 (App Router), TypeScript |
| Wallet / Web3 | Wagmi v2, viem v2, RainbowKit v2 |
| Styling | Tailwind CSS v3 |
| Hosting | Vercel (frontend), Nexus L1 (contracts) |
| CI | GitHub Actions |

---

## Security Notes

- **No secrets are committed.** The `.env` file is gitignored. Only `.env.example` is tracked.
- The deployer key used for these deployments is a **fresh, dedicated key** funded with the minimum NEX required. It should not hold significant value.
- Contracts use `ReentrancyGuard` and custom errors throughout.
- A formal audit is recommended before handling significant value on mainnet.

---

## License

[MIT](LICENSE) — 2026.
