# NexEscrow frontend

Next.js (App Router) + wagmi + viem + RainbowKit dApp for `NexusEscrow.sol`. See the
[repo root README](../README.md) for the full picture and
[`docs/THREAT_MODEL.md`](../docs/THREAT_MODEL.md) for the security model.

**Status: testnet / unaudited.** The UI labels this explicitly and mainnet is disabled
unless an operator opts in.

## Setup

```bash
pnpm install
cp .env.example .env.local   # set the chain + per-chain contract address
pnpm dev
```

## Chain configuration (read before changing)

- The build **defaults to a testnet** (BOT Chain Bohr, 968). It never defaults to mainnet.
- Mainnet ids in `NEXT_PUBLIC_CHAIN_ID` are ignored (fail closed to testnet) unless
  `NEXT_PUBLIC_ALLOW_MAINNET=true`; the UI shows a visible warning when it had to
  override a request.
- Contract addresses are **per chain** (`NEXT_PUBLIC_ESCROW_ADDRESS_<chainId>`). There is
  no shared address variable, and no cross-chain fallback.
- Every write goes through `useEscrowWrite`, which asserts
  `connectedChainId === selectedChainId` and passes an explicit `chainId` to the wallet.
  Wrong-network transactions are blocked before submission; the status bar offers a
  one-click switch.
- If the selected chain has no configured contract, the UI is read-only and writes are
  disabled rather than sent to the zero address.

Supported chains: Nexus Testnet (3945), BOT Chain Bohr (968), and — opt-in only —
Nexus Mainnet (3946) and BOT Chain Mainnet (677).

## Structure

- `src/lib/chain.ts` — all chain definitions, selection/fail-closed logic, per-chain
  addresses, explorer helpers, wrong-network guard.
- `src/lib/wagmi.ts` — wagmi/RainbowKit config (testnets only unless mainnet allowed).
- `src/lib/contract.ts`, `src/lib/nexusEscrowAbi.ts` — ABI wiring (ABI generated from
  `contracts/out/NexusEscrow.sol/NexusEscrow.json`).
- `src/lib/indexer/` — agreement index abstraction: bounded RPC log scan adapter +
  HTTP indexer adapter. The production ingestion design is in `../docs/INDEXING.md`.
- `src/hooks/useEscrowWrite.ts` — guarded writes with the full
  wallet → pending → mined → confirmed → reconciled lifecycle.
- `src/hooks/useMyAgreements.ts` — agreement discovery for the connected wallet.
- `src/app/` — landing (`/`), dashboard (`/dashboard`), create form (`/create`),
  agreement detail (`/agreement/[id]`).
