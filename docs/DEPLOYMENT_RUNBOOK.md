# Deployment Runbook

> **This sprint does not deploy to any mainnet.** Mainnet configuration is documented
> and opt-in only. The contract is unaudited.

## 0. Safety rules

1. Testnet first, always. The intended first deployment is **BOT Chain Bohr, chain 968**.
2. Never put a funded mainnet key in the repository or an environment file that can be
   committed. `.env` is gitignored; `.env.example` contains placeholders only.
3. Mainnet script execution is refused unless `ALLOW_MAINNET_DEPLOYMENT=true` is set
   explicitly. Do not set that flag for 677/3946 until the mainnet gates in
   `docs/BOTCHAIN_INTEGRATION.md` §21 are all satisfied.
4. No claims of audit or production readiness may accompany a deployment.

## 1. Preconditions

- Foundry installed (`forge`, `cast`); pnpm for OpenZeppelin.
- Working tree clean and CI green at the commit being deployed.
- `forge test` green (default profile at minimum; CI profile preferred).
- Deployer wallet funded with testnet native tokens.
- Owner and fee-recipient addresses decided (multisig recommended for anything beyond
  testnet experiments).
- Target chain's explorer verification flavour confirmed.

```shell
cd contracts
pnpm install --frozen-lockfile
forge build
forge test                         # 112 tests
FOUNDRY_PROFILE=ci forge test      # heavier fuzz/invariant campaign
forge fmt --check
```

## 2. Environment

```shell
cp .env.example .env
# edit .env:
#   PRIVATE_KEY=<burner testnet key>
#   ESCROW_OWNER=<owner address, optional; defaults to deployer>
#   ESCROW_FEE_RECIPIENT=<fee recipient, optional; defaults to deployer>
#   ALLOW_MAINNET_DEPLOYMENT=false
```

Never commit `.env`. Never paste a key into a command line that lands in shell history
where avoidable; prefer `source .env` with `forge` reading the env var.

## 3. BOT Chain Bohr testnet (968) — intended first deployment

```shell
source .env
forge script script/DeployNexusEscrow.s.sol:DeployNexusEscrow \
  --rpc-url bot_testnet --broadcast \
  --verify --verifier blockscout --verifier-url https://scan.bohr.life/api/ -vvvv
```

Record from the output / broadcast artifact (`broadcast/DeployNexusEscrow.s.sol/968/`):

- contract address
- deployment transaction hash and block number
- owner and fee recipient actually used
- compiler version and settings (`solc 0.8.26`, optimizer 200, via_ir, evm cancun)

## 4. Nexus testnet (3945) — alternative

```shell
forge script script/DeployNexusEscrow.s.sol:DeployNexusEscrow \
  --rpc-url nexus_testnet --broadcast \
  --verify --verifier blockscout --verifier-url https://testnet.explorer.nexus.xyz/api/ -vvvv
```

Nexus explorers run Blockscout, not Etherscan; no API key is required.

## 5. Post-deployment checks

```shell
ADDR=<deployed address>
RPC=<rpc url>
cast code $ADDR --rpc-url $RPC                         # non-empty
cast call $ADDR "owner()(address)" --rpc-url $RPC      # the intended owner
cast call $ADDR "feeRecipient()(address)" --rpc-url $RPC
cast call $ADDR "protocolFeeBps()(uint16)" --rpc-url $RPC   # 100 (1%) default
cast call $ADDR "nextAgreementId()(uint256)" --rpc-url $RPC # 0
```

Smoke-test the full lifecycle with small amounts, from distinct accounts:

1. `createAgreement(seller, arbiter, address(0), [amount], 0)`
2. `fund(id)` with exact value
3. `approveMilestone(id)` → expect `MilestoneReleased` + `AgreementCompleted`
4. `raiseDispute`/`resolveDispute` on a second agreement
5. Verify seller balance delta == amount − fee and `accruedFees` == fee

A complete raw-output example of exactly this flow (on a simulated node) is in
`docs/TESTNET_EVIDENCE.md`.

## 6. Frontend configuration

```shell
cd frontend
cp .env.example .env.local
#   NEXT_PUBLIC_CHAIN_ID=968
#   NEXT_PUBLIC_ESCROW_ADDRESS_968=<address>
#   NEXT_PUBLIC_DEPLOY_BLOCK_968=<block>
#   NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=<optional>
```

Then `pnpm lint && pnpm typecheck && pnpm build`. The build must keep
`NEXT_PUBLIC_ALLOW_MAINNET` unset for testnet deployments.

## 7. Verification of the guard (before any mainnet consideration)

```shell
# Simulated 677 node, no flag → must revert with MAINNET DEPLOYMENT BLOCKED:
forge script script/DeployNexusEscrow.s.sol:DeployNexusEscrow --rpc-url <677 rpc>

# With the flag (dry-run only; do NOT add --broadcast):
ALLOW_MAINNET_DEPLOYMENT=true forge script script/DeployNexusEscrow.s.sol:DeployNexusEscrow --rpc-url <677 rpc>
```

## 8. Mainnet (677 / 3946) — opt-in procedure, gated

Do not run this section until every gate in `docs/BOTCHAIN_INTEGRATION.md` §21 is
satisfied and an independent security review has been completed and published.

1. Independent review complete; findings addressed; report archived.
2. `ALLOW_MAINNET_DEPLOYMENT=true` exported for the deploy session only.
3. Owner = multisig; fee recipient = multisig or treasury; documented custody.
4. Deploy with the same commands as §3/§4 using `bot_mainnet` / `nexus_mainnet`.
5. Verify source on the explorer; record all addresses hashes in the repo docs.
6. Announce plainly that the contract is **not** audited until it is.

## 9. Rollback / incident procedure

The contract is non-upgradeable; there is no code rollback. The available levers:

| Situation | Action |
|---|---|
| Suspected exploit in progress | Owner pauses the contract (blocks create/fund/milestones/disputes; fee withdrawal remains). Publishing the pause tx is the fastest public signal. |
| Accounting suspicion | Pause, then verify with on-chain reads; do not unpause until the failure mode is understood. |
| Bug requires code change | Deploy a fixed contract to a new address; coordinate off-chain migration; old agreements only settle through their existing arbiter path. |
| Frontend bug | Revert the frontend deployment; the contract remains the source of truth. |
| Key compromise (owner) | Transfer ownership via 2-step handoff from the compromised key is impossible without the key; treat as critical and pause if the compromised key is the owner. |

Because principal cannot be moved by the owner, a pause is an availability action, not
a rescue action. Document this trade-off in any incident communication.
