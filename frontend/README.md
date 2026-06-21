# NexEscrow — Frontend

Next.js 14 (App Router) frontend for the NexEscrow dApp on Nexus L1.

## Live URL

> **[https://nexescrow.vercel.app](https://nexescrow.vercel.app)**

## Stack

- **Next.js 14** (App Router, TypeScript)
- **Wagmi v2 + viem v2** — React hooks for Ethereum
- **RainbowKit v2** — wallet connection UI
- **Tailwind CSS v3** — styling

## Development

```bash
npm install --legacy-peer-deps
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

## Build

```bash
npm run build
npm start
```

## Contract Config

ABIs and deployed addresses are in `src/contracts/index.ts`.  
To regenerate after a new deployment, run from the repo root:

```bash
node copyArtifacts.js
```

## Deployment

Auto-deployed to Vercel on every push to `main`.  
Root directory: `frontend` | Framework: Next.js
