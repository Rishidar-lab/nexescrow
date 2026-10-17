# NexEscrow contracts

Foundry project for `NexusEscrow.sol` — a chain-agnostic, non-custodial,
milestone-based escrow. See the [repo root README](../README.md) for the full
picture and [`docs/THREAT_MODEL.md`](../docs/THREAT_MODEL.md) for the security model.

**Status: unaudited, testnet stage.** Do not deploy to a mainnet.

## Usage

```shell
pnpm install        # OpenZeppelin Contracts (via node_modules, not a git submodule)
forge build
forge test
forge coverage --ir-minimum --report summary
forge fmt
```

Fuzz runs default to 1024 per test and invariants to 128 runs x 64 depth. A heavier
CI profile is available: `FOUNDRY_PROFILE=ci forge test`.

## Networks

Named RPC endpoints in `foundry.toml`:

| Profile name | Chain ID | Purpose |
|---|---|---|
| `bot_testnet` | 968 | BOT Chain Bohr testnet (primary integration target) |
| `nexus_testnet` | 3945 | Nexus testnet |
| `bot_mainnet` | 677 | BOT Chain mainnet — **blocked by the deploy script by default** |
| `nexus_mainnet` | 3946 | Nexus mainnet — **blocked by the deploy script by default** |

## Deploying

```shell
cp .env.example .env   # PRIVATE_KEY + optional ESCROW_OWNER / ESCROW_FEE_RECIPIENT
source .env

# BOT Chain Bohr testnet (968) — the intended first deployment
forge script script/DeployNexusEscrow.s.sol:DeployNexusEscrow \
  --rpc-url bot_testnet --broadcast \
  --verify --verifier blockscout --verifier-url https://scan.bohr.life/api/ -vvvv

# Nexus testnet (3945)
forge script script/DeployNexusEscrow.s.sol:DeployNexusEscrow \
  --rpc-url nexus_testnet --broadcast \
  --verify --verifier blockscout --verifier-url https://testnet.explorer.nexus.xyz/api/ -vvvv
```

Mainnet chains (677 / 3946) revert inside the script unless
`ALLOW_MAINNET_DEPLOYMENT=true` is set. That flag exists for documented, opt-in
mainnet configuration only — this sprint does not deploy to mainnet.

Nexus and BOT Chain explorers are Blockscout-flavoured; verification uses
`--verifier blockscout --verifier-url <explorer>/api/`, no API key required.
Confirm the verifier flavour before broadcasting on a new chain.

The full procedure, including post-deploy checks and rollback, is in
[`docs/DEPLOYMENT_RUNBOOK.md`](../docs/DEPLOYMENT_RUNBOOK.md).
