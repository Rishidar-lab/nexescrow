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

```shell
cp .env.example .env   # fill in PRIVATE_KEY and NEXUS_TESTNET_RPC_URL
source .env
forge script script/DeployNexusEscrow.s.sol:DeployNexusEscrow \
  --rpc-url nexus_testnet --broadcast --verify -vvvv
```

`ESCROW_OWNER` and `ESCROW_FEE_RECIPIENT` are optional env vars; both default to the
deployer address if unset.
