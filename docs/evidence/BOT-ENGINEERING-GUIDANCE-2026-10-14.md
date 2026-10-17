# BOT Chain engineering guidance — 2026-10-14

> Source: technical email thread `NexEscrow × BOT Chain — additional network inquiry`.
> Leon relayed guidance supplied by Cisco from BOT Chain node/backend engineering.
> This document records the guidance as received and separates it from NexEscrow's
> own application-level safety choices.

## Confirmed guidance

### `eth_getLogs`

- Recommended query range: **2,000 blocks per request**.
- Reported configured rate limit: **none**.

NexEscrow response:

- the direct-RPC adapter already defaulted to 2,000-block windows;
- BOT 968/677 now enforce a 2,000-block ceiling even if a larger client chunk is
  requested;
- the scanner remains bounded from the deployment block and never scans from genesis
  by default.

### Receipt confirmations

- Bohr testnet (chain ID **968**): **2 blocks**.
- BOT Chain mainnet (chain ID **677**): **2 blocks**.

NexEscrow response:

- `writeReceiptConfirmations` is explicitly set to 2 for both BOT networks;
- the separate `indexingSafetyDepth` remains **12 blocks** as a conservative NexEscrow
  application policy until BOT Chain provides reorganisation/finality guarantees;
- the 12-block indexing depth is **not** represented as BOT Chain's recommended
  finality depth.

### EVM target

- Recommended EVM target: **`cancun`**.
- Cisco's reference Hardhat example uses **Solidity 0.8.28** with
  `settings.evmVersion = "cancun"`.

NexEscrow response:

- `contracts/foundry.toml` already targets `evm_version = "cancun"`;
- the existing validated Bohr deployment used Solidity **0.8.26** and Cancun and was
  successfully deployed, exercised and explorer-verified;
- NexEscrow remains pinned to its exact Solidity 0.8.26 pragma because the email did
  not state that 0.8.28 is a required minimum. A compiler migration is therefore not
  introduced merely to copy the example.

## Still not clarified by BOT Chain

Leon explicitly stated that the following are not yet clarified:

1. specific retry guidance;
2. reorganisation handling;
3. finality guarantees.

Opcode/precompile limitations were also not supplied in this response.

## NexEscrow-owned safety policy while those items remain open

### Retry

The direct-RPC log scanner uses a bounded application retry policy for clearly
transient gateway/transport failures only:

- maximum total attempts: **3**;
- delays: 250 ms, then 500 ms before subsequent attempts;
- retryable classes include HTTP 429/502/503/504, timeout, network/fetch failures;
- semantic/RPC errors such as execution reverts, invalid params or method-not-found
  are not retried.

This is a **NexEscrow application policy**, not BOT Chain guidance.

### Reorganisation safety

NexEscrow retains a 12-block indexing safety depth and rescans/reconciles logs by
canonical event identity. The contract state remains the source of truth. This is a
conservative application policy pending explicit BOT Chain reorganisation/finality
recommendations.

## Mainnet status

Nothing in the 2026-10-14 guidance is treated as mainnet clearance.

```
BOT MAINNET 677: NOT DEPLOYED · NOT ENABLED · NOT PRODUCTION READY
```

The existing explicit mainnet gates remain in force, including independent security
review, production indexing/reorg monitoring, custody/key-management decisions,
incident/migration procedures and BOT Chain engineering sign-off.
