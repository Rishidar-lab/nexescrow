# NexEscrow frontend

Next.js (App Router) + wagmi + viem + RainbowKit dApp for `NexusEscrow.sol`. See the
[repo root README](../README.md) for the full picture.

## Setup

```bash
pnpm install
cp .env.example .env.local   # fill in the deployed contract address and RPC URL
pnpm dev
```

Required env vars (see `.env.example`):

- `NEXT_PUBLIC_ESCROW_ADDRESS` — deployed `NexusEscrow` address
- `NEXT_PUBLIC_NEXUS_RPC_URL` / `NEXT_PUBLIC_NEXUS_EXPLORER_URL` — Nexus L1 endpoints
- `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` — free project ID from
  [cloud.reown.com](https://cloud.reown.com); without it, WalletConnect won't work but
  injected wallets (MetaMask, etc.) still do

## Structure

- `src/lib/chain.ts`, `src/lib/wagmi.ts` — Nexus L1 chain + wagmi/RainbowKit config
- `src/lib/contract.ts`, `src/lib/nexusEscrowAbi.ts` — contract address/ABI wiring
  (ABI is generated from `contracts/out/`, see the comment at the top of that file)
- `src/hooks/useMyAgreements.ts` — discovers agreements for the connected wallet by
  scanning `AgreementCreated` logs; fine for testnet scale, swap for an indexer in prod
- `src/hooks/useAgreement.ts` — reads a single agreement + its milestones
- `src/app/` — dashboard (`/`), create form (`/create`), agreement detail (`/agreement/[id]`)
