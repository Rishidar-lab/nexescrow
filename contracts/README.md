# NexEscrow contracts

Foundry project for `NexusEscrow.sol`. See the [repo root README](../README.md) for
the full picture (architecture, frontend, security notes).

## Usage

```shell
pnpm install        # OpenZeppelin Contracts (via node_modules, not a git submodule)
forge build
forge test
forge coverage --ir-minimum --report summary
forge fmt
```

## Deploying

`nexus_mainnet` and `nexus_testnet` are pre-configured in `foundry.toml` with Nexus's
official RPC endpoints. **`nexus_mainnet` is real mainnet** — a funded deployer key
there spends real NEX and, once deployed, the contract holds real user funds. This
contract is unaudited; deploy to `nexus_testnet` while iterating.

```shell
cp .env.example .env   # fill in PRIVATE_KEY (and ESCROW_OWNER/ESCROW_FEE_RECIPIENT if desired)
source .env

# Testnet
forge script script/DeployNexusEscrow.s.sol:DeployNexusEscrow \
  --rpc-url nexus_testnet --broadcast \
  --verify --verifier blockscout --verifier-url https://testnet.explorer.nexus.xyz/api/ \
  -vvvv

# Mainnet — only when you actually mean it
forge script script/DeployNexusEscrow.s.sol:DeployNexusEscrow \
  --rpc-url nexus_mainnet --broadcast \
  --verify --verifier blockscout --verifier-url https://explorer.nexus.xyz/api/ \
  -vvvv
```

Nexus explorers run Blockscout, not Etherscan — verification uses
`--verifier blockscout --verifier-url <explorer>/api/`, no API key required.
