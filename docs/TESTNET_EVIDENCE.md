# Testnet Evidence Log

> Date of record: 2026-10-08 (UTC). All raw outputs referenced here are committed under
> `docs/evidence/`.

## 0a. Live BOT Bohr run (2026-10-08) — added after the local simulation

The guarded wrapper and the E2E harness were subsequently run against **live BOT Chain
Bohr (968)** with throwaway testnet keys:

- RPC capability matrix: `docs/evidence/bot-rpc-capability.json` + `.md`
  (`eth_getLogs` works on both official endpoints; no hard range cap).
- Deployment + lifecycle: `docs/evidence/bot-968/` — deployment manifest, transaction
  list, balance snapshots, raw events, direct-state reads and a lifecycle report with
  **23/23 checks passed** (release, dispute, arbitration, event-vs-direct reconciliation,
  conservation).
- Contract: `0x6448668ae9cbbc41617c2bd5e4f29279320a2700`, verified on
  https://scan.bohr.life/address/0x6448668ae9cbbc41617c2bd5e4f29279320a2700
- A second, earlier wrapper-validation deployment (`0xbb32...`, owner = the well-known
  public Anvil key) is marked superseded in
  `docs/evidence/bot-968/deployments-registry.json`.

## 0. Honest summary

| Claim | Status |
|---|---|
| BOT Chain Bohr (968) RPC reachable, reports chain id 968 | **Verified** (read-only) |
| NexusEscrow deploys and runs end-to-end on a chain-968 node | **Verified** (local Anvil and **live BOT Bohr**) |
| Deployed to public BOT Chain Bohr testnet | **DONE** (2026-10-08, unaudited testnet instance; see §0a) |
| Live lifecycle + event/state reconciliation + conservation | **23/23 checks passed** (`docs/evidence/bot-968/lifecycle-report.md`) |
| Source verified on scan.bohr.life | **DONE** (`is_verified: true`, solc 0.8.26, evm cancun) |
| `eth_getLogs` capability on 968 and 677 | **Verified enabled**; no hard range cap (`docs/evidence/bot-rpc-capability.md`) |
| Deployed to BOT mainnet 677 | **NOT DONE, and explicitly out of scope** |
| Mainnet deployment blocked by default | **Verified** (script reverts without the opt-in flag) |
| Contract tests / invariants | **Verified** (112 tests, 0 failures) |
| Frontend lint / typecheck / build | **Verified** |
| Independent security audit | **NOT DONE — none claimed** |

The local simulated chain-968 run proves the deployment script, constructor, and
lifecycle work on a node configured as 968. The live BOT Bohr run additionally proves
Bohr-specific behaviour (real blocks, real gas, explorer verification). Neither is an
audit, and no production/mainnet claim is made.

## 1. BOT Chain Bohr read-only verification

Raw output: `docs/evidence/bot-bohr-rpc-check.txt`.

```
UTC=2026-10-08T17:53:43Z
cmd: cast chain-id --rpc-url https://rpc.bohr.life
968
cmd: cast block-number --rpc-url https://rpc.bohr.life
26163388
UTC=2026-10-08T17:53:45Z
```

## 1b. Nexus RPC reachability (observed limitation)

At 2026-10-08T17:57Z, both `testnet.rpc.nexus.xyz` and `mainnet.rpc.nexus.xyz` failed
DNS resolution from the test environment (`getent hosts`: no address); `rpc.bohr.life`
resolved and responded. Nexus testnet readiness is therefore **unverified here** — the
Nexus deployment path uses the same guarded script but was not exercised against a
live node. This should be re-checked before any Nexus deployment claim.

## 2. Local deployment on a simulated chain 968

`anvil --chain-id 968`; deployer/first Anvil account; raw log
`docs/evidence/local-968-deploy.log` (first run) and broadcast artifact
`docs/evidence/broadcast-968/run-latest.json` (fresh run).

- Deployment tx: `0xb8401756dcf794467400f867ffbda9d390411f68b2d1fe65da3be56248548905`
- Contract address: `0x5fbdb2315678afecb367f032d93f642f64180aa3`
- Script output confirms `Chain ID: 968`, `Testnet/non-mainnet deployment (good)`, and
  prints the frontend env vars to set.
- Post-deploy reads: `owner()` = deployer, `feeRecipient()` = deployer,
  `protocolFeeBps()` = `100` (1%), `nextAgreementId()` = `0`.

## 3. Full lifecycle on the simulated 968 node

Raw log: `docs/evidence/local-968-lifecycle.log`. Agreement: milestones
`[1.5 BOT, 0.5 BOT]`, funded with exactly `2.0 BOT`; then `approveMilestone` on M0 and
`raiseDispute`/`resolveDispute(6000)` on M1.

| Step | Tx hash | Status | Block |
|---|---|---|---|
| createAgreement | `0xe8925e9a8360fd46045cf5cd51339813d2c9d22d2b220cd7cf281cbbcdfbe19f` | success | 2 |
| fund (2.0 BOT) | `0x425e653e0f7911801509ec34bab3df0f53a0434e50605c1a6f686860bfbbde46` | success | 3 |
| approveMilestone (1.5) | `0x416f2d72d56882e64b0d515bbe7668f4552210ba6867d149399f2f283591cc45` | success | 4 |
| raiseDispute (seller) | `0x15edf2ed13cc0b9fb30d0ede45a0ca2a87dfcf43cd766659a4643eaf2d91b870` | success | 5 |
| resolveDispute(6000) (arbiter) | `0xb5b63718c63b5c7f5e72c091a5836488f11bc2e9672f9ecfdd59b88bf13f5f8e` | success | 6 |

Recorded state after resolution:

- Seller balance: `10000000000000000000000` → `10001682976321603944485`
- Escrow balance: `17000000000000000` (= `accruedFees(address(0))` exactly)
- Agreement: token `0x0`, total `2e18`, feeBps `100`, status `2` (Completed),
  milestoneCount `2`, nextMilestone `2`
- Milestones: `[(1.5e18, 1 Released), (0.5e18, 3 Resolved)]`

Conservation check (all values in wei, fee 1%):

```
M0: 1.5e18 = 1.485e18 seller + 0.015e18 fee
M1: 0.5e18 = 0.3e18 buyer refund + 0.198e18 seller + 0.002e18 fee
payouts (1.485 + 0.3 + 0.198) + fees (0.015 + 0.002) = 2.0e18 deposited  ✓
escrow remaining == accrued fees == 0.017e18                          ✓
```

The seller's net balance delta (`1.682976321603944485`) is `1.683` minus the gas the
seller paid to submit `raiseDispute` (`0.000023678396055515` at 2 gwei); gas is not an
escrow accounting term.

## 4. Mainnet guard verification

Raw log: `docs/evidence/mainnet-guard-677.log` (simulated chain 677, local Anvil).

- Without the opt-in flag:
  `[Revert] MAINNET DEPLOYMENT BLOCKED: set ALLOW_MAINNET_DEPLOYMENT=true only after independent security review`
- With `ALLOW_MAINNET_DEPLOYMENT=true`: dry-run only (no `--broadcast`). Proof that
  nothing was broadcast: after the dry run, block height remained `0` and
  `cast code <address>` returned `0x` (no contract on-chain).

## 5. Contract test evidence

Raw output: `docs/evidence/contracts-test-run.txt`.

```
Ran 7 test suites ... 112 tests passed, 0 failed, 0 skipped (112 total tests)
```

Suite breakdown: 33 lifecycle, 20 authorization, 19 disputes, 21 admin, 12 token-edge,
4 security/fuzz, 3 stateful invariants (128 runs × 64 depth = 8,192 handler calls).

Fuzz/invariant runs: default `1024` fuzz runs per test; invariants `128 × 64`;
CI profile `4096` fuzz runs and `256 × 128` invariants
(`contracts/foundry.toml`, profiles `default`/`ci`).

## 6. Coverage

Raw output: `docs/evidence/coverage-summary.txt`
(`forge coverage --ir-minimum --report summary`):

```
src/NexusEscrow.sol | 98.56% lines | 98.37% statements | 97.44% branches | 100% functions
```

## 7. Static analysis

Raw output: `docs/evidence/slither.txt` (Slither 0.11.5, `--filter-paths
'node_modules|test'`): 8 informational results — one uninitialized-local false
positive (`total` is initialized to 0 by Solidity), four timestamp-comparison infos
(funding deadlines, intentional), one low-level native `call` info (intentional; the
only way to send the native asset), one unindexed event-address info. No high or
medium findings. Warnings were not suppressed to force a green result.

## 8. Frontend evidence

Raw output: `docs/evidence/frontend-build.txt` — `pnpm lint` clean,
`next typegen && tsc --noEmit` clean, `next build` succeeds (6 routes).
Raw output: `docs/evidence/chain-resolution.txt` — fail-closed resolver results:

| Requested `NEXT_PUBLIC_CHAIN_ID` | Result |
|---|---|
| unset | 968 (BOT Bohr testnet) |
| 3946 (mainnet), allow unset | 968 + visible warning |
| 3946, `ALLOW_MAINNET=true` | 3946 |
| 3945 | 3945 |
| 677, `ALLOW_MAINNET=true` | 677 (opt-in only) |
| 1 (unknown) | 968 + visible warning |

## 9. Reproduction

```shell
# 1. Chain 968 local node
anvil --chain-id 968 --port 8600

# 2. Deploy (same script as testnet)
cd contracts
PRIVATE_KEY=0xac0974... # anvil account 0 (public test key — never use on real nets)
forge script script/DeployNexusEscrow.s.sol:DeployNexusEscrow \
  --rpc-url http://127.0.0.1:8600 --broadcast

# 3. Lifecycle: see docs/evidence/local-968-lifecycle.log for the exact cast commands

# 4. Guard: anvil --chain-id 677 --port 8601; run the script without the flag
```

## 10. What this evidence does not establish

- No mainnet deployment claim; mainnet remains untested and out of scope.
- No audit, review, or endorsement by BOT Chain or anyone else.
- No real-user, TVL, or production-usage claims; the live instance is a throwaway
  validation deployment owned by discarded keys, not a service.
- No guarantee of BOT Bohr RPC behaviour under load (transient 503s were observed),
  finality depth, or long-term explorer availability (tracked as open questions in
  `docs/BOTCHAIN_INTEGRATION.md` §20).
