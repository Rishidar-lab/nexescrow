# BOT Chain Integration Dossier

> Prepared for BOT Chain engineering review. Date: 2026-10-08 (UTC).
> Status: **unaudited, not production ready, not deployed to BOT Chain.**
> This document contains no claims of adoption, users, TVL, audits, or production use.

---

## 1. NexEscrow overview

NexEscrow is a non-custodial, milestone-based escrow protocol. A buyer locks the full
agreement amount in a single immutable contract; the seller is paid milestone by
milestone as the buyer approves each one; disagreements on a milestone are resolved by
a named third-party arbiter. The contract is a single, non-upgradeable Solidity 0.8.26
contract with no proxy, no admin fund access, and no external dependencies beyond
OpenZeppelin and the settlement asset (native or ERC-20).

Repository: `Rishidar-lab/nexescrow` (MIT). Contracts: `contracts/src/NexusEscrow.sol`.

## 2. Architecture

- One contract, one storage layout, agreements keyed by an incrementing `uint256` id.
- Per agreement: buyer, seller, arbiter, token (`address(0)` = native), total,
  snapshotted fee (bps), status, created/funding-deadline timestamps, milestone array,
  cursor.
- Milestones release strictly in order. The cursor (`nextMilestone`) is the only
  milestone that any action can touch.
- `ReentrancyGuard` (single lock) on every fund-moving entry point; checks-effects-
  interactions ordering; `Pausable` + `Ownable2Step` for admin availability controls.
- Non-upgradeable by design: no proxy, no `delegatecall`, no `selfdestruct`, no
  initializer, no migration admin.
- Contract runtime size: 6,309 bytes (well under the 24,576-byte EIP-170 limit).

## 3. Escrow lifecycle

```
createAgreement ─▶ AwaitingFunding ──fund(buyer, full amount)──▶ Active
                        │                                          │
                        │ cancelBeforeFunding                      │ approveMilestone (buyer) or
                        ▼ (either party; anyone after deadline)    │ raiseDispute (party) → resolveDispute (arbiter)
                    Cancelled (terminal)                           ▼
                                                       Completed (terminal, cursor == count)
```

- Creation moves no funds.
- Funding is all-or-nothing, exactly the total.
- The funding deadline is optional; `0` means "no deadline" and only the parties can
  then cancel an unfunded agreement.
- There is no timeout-based release and no mutual-cancel path after funding (see §13).

## 4. Participant roles

| Role | Set by | Can do | Cannot do |
|---|---|---|---|
| Buyer | `msg.sender` at creation | fund, approve milestones, raise dispute, cancel while unfunded | seize funds, skip milestones, force resolution |
| Seller | named at creation | raise dispute, cancel while unfunded | release funds, resolve disputes |
| Arbiter | named at creation (must differ from buyer and seller) | resolve the current disputed milestone | act without a dispute, touch other milestones/agreements |
| Owner | constructor | pause/unpause, set fee ≤ 10%, rotate fee recipient, 2-step ownership transfer | move principal, resolve disputes, alter agreements |
| Fee recipient | constructor, rotatable by owner | withdraw accrued fees | withdraw principal or more than accrued |

## 5. Arbitration model

Summary of `docs/ARBITRATION_MODEL.md`:

- Either party raises a dispute on the current pending milestone; it freezes.
- The arbiter splits that milestone by basis points: `buyerBps ∈ [0, 10000]`.
- Fee applies only to the seller's share; a full buyer refund is untaxed.
- `buyerAmount + sellerAmount + fee == milestone.amount` exactly, for every input.
- The arbiter is selected per agreement by the buyer at creation; the only enforced
  neutrality check is `arbiter != buyer && arbiter != seller`.
- Liveness dependency: a silent arbiter freezes the disputed milestone. No timeout
  fallback exists by design; this is disclosed as a known risk.

## 6. Asset flow

- **In:** native `msg.value` or ERC-20 `safeTransferFrom`, exactly `totalAmount`.
- **Out:** per-milestone seller payout (release or seller side of arbitration), buyer
  refund on arbitration, and fee withdrawal to the fee recipient.
- **Fee-on-transfer tokens are rejected at funding** (balance-delta check): the
  agreement never becomes silently under-collateralized.
- No interest, yield, wrapping, bridging, or rehypothecation. Funds are idle until a
  milestone action or fee withdrawal moves them.

## 7. Permissions

- `fund`, `approveMilestone`: buyer only.
- `raiseDispute`: buyer or seller only.
- `resolveDispute`: arbiter of that agreement only.
- `cancelBeforeFunding`: either party, or any address after the funding deadline.
- `withdrawFees`: current fee recipient only.
- `pause` / `unpause` / `setProtocolFee` / `setFeeRecipient` / ownership transfer:
  owner only.
- There is no special-cased address, no allowlist, and no privileged fund path.

## 8. Admin powers

Owner powers are limited to availability (`pause`/`unpause`) and fee configuration
(`setProtocolFee` ≤ 1,000 bps, `setFeeRecipient`). Fee changes apply only to
agreements created afterwards — `feeBps` is snapshotted per agreement. The owner
cannot resolve disputes, cannot move escrow principal, cannot mint, and cannot
upgrade. `Ownable2Step` means ownership handoff requires the new owner to accept.

## 9. Non-upgradeability

Deployed bytecode is final. There is no proxy pattern to point elsewhere, no
initialization re-run, and no admin sweep. "Fixing" a deployment means deploying a new
contract and migrating off-chain; this is a deliberate trust-minimization choice and
must be weighed against the operational cost of irreversibility before any mainnet
deployment.

## 10. Supported token behaviour

| Token | Support |
|---|---|
| Standard ERC-20 and no-return (USDT-style) | Yes |
| Fee-on-transfer / deflationary | **Rejected at fund** (`UnsupportedTokenBehavior`) |
| Rebasing / elastic supply | Unsupported (documented) |
| Returns `false` on transfer | Fails closed (`SafeERC20FailedOperation`) |
| Malicious/reentrant | Blocked by `ReentrancyGuard` (tested) |
| Arbitrary decimals | Supported (raw units) |
| Native asset | Supported (`address(0)`) |

Full matrix: `docs/TOKEN_AND_FUNDS_FLOW.md` §6.

## 11. Fee model

- Default 1% (`100` bps), hard-capped at 10% (`1_000` bps) in the contract.
- Charged only on the seller's portion of a released or arbitrated milestone; buyer
  refunds are never taxed.
- Snapshotted at creation; owner changes never affect in-flight agreements.
- Accrued per token; withdrawable only by the current fee recipient; not blocked by
  pause; backed by the contract's balance (invariant-tested).

## 12. Security controls

- Reentrancy guard across all fund-moving functions; CEI.
- Pause switch for new agreements/funding/milestones/disputes; fee withdrawal and admin
  config remain live while paused.
- Role separation enforced on every entry point (buyer/seller/arbiter/owner/fee
  recipient).
- Validation: no zero-address participants; arbiter must differ from both parties;
  1–50 milestones; no zero amounts; sum ≤ `uint128` max; deadline in the future on
  creation.
- Exact funding (native value check; ERC-20 balance-delta check).
- No `delegatecall`, no upgrade path, no privileged principal access.
- 112 Foundry tests including adversarial/authorization/token-edge suites and a
  stateful invariant suite; fuzz runs at 1,024 per test (default) and 4,096 (CI
  profile); invariants at 128×64 (default) and 256×128 (CI).

## 13. Known risks (disclosed)

1. **Silent arbiter** freezes a disputed milestone indefinitely (no timeout).
2. **No funded mutual-cancel**: abandoning a funded agreement requires arbitration,
   milestone by milestone.
3. **Pause is a liveness lever**: a compromised/malicious owner can freeze all
   agreement paths; accounting cannot be corrupted, and unpause restores operation.
4. **Rebasing/blocklist tokens** are not defended against.
5. **Reverting native receivers** block their own payouts (buyer chooses the seller).
6. **Fee-recipient rotation** moves accrued-but-unwithdrawn fees to the new recipient.
7. **Non-upgradeable**: defects cannot be patched in place.
8. **Unaudited**: this code has not been independently reviewed.

## 14. Testing status

- `forge test`: 112 tests, 0 failures (7 suites).
- Stateful invariants: exact solvency for native and ERC-20, cursor/state consistency,
  milestone-sum, id monotonicity.
- Coverage (foundry, `--ir-minimum`): NexusEscrow.sol **98.56% lines / 98.37%
  statements / 97.44% branches / 100% functions**.
- Slither 0.11.5: 8 informational-level results (1 uninitialized-local false positive,
  4 timestamp comparisons — by design for funding deadlines, 1 low-level native call —
  intentional, 1 unindexed event-address info). No high/medium findings.
- Local end-to-end deployment and lifecycle on a simulated chain 968 with raw logs:
  `docs/TESTNET_EVIDENCE.md`.
- **No independent audit has been performed; none is claimed.**

## 15. BOT Chain 968 configuration (BOT Bohr testnet)

| Parameter | Value |
|---|---|
| Chain ID | `968` |
| RPC | `https://rpc.bohr.life` |
| Explorer | `https://scan.bohr.life` |
| Native symbol | `BOT` (18 decimals) |
| Foundry endpoint | `bot_testnet` in `contracts/foundry.toml` |
| Frontend chain | `BOT Chain Bohr Testnet` in `frontend/src/lib/chain.ts` |
| Default chain | Yes — this build defaults to 968 |
| Deployment status | **Not deployed** (no operator credentials/faucet funds configured) |

Read-only reachability verification (2026-10-08 UTC): `cast chain-id` = `968`;
`cast block-number` = `26162704`. Local end-to-end deployment on a simulated 968 node
succeeded (see evidence doc).

Deploy command (when credentials exist):

```shell
forge script script/DeployNexusEscrow.s.sol:DeployNexusEscrow \
  --rpc-url bot_testnet --broadcast \
  --verify --verifier blockscout --verifier-url https://scan.bohr.life/api/ -vvvv
```

## 16. Proposed 677 configuration (BOT Chain mainnet — documented, opt-in only)

| Parameter | Value |
|---|---|
| Chain ID | `677` |
| RPC | `https://rpc.botchain.ai` |
| Explorer | `https://scan.botchain.ai` |
| Native symbol | `BOT` (18 decimals) |
| Foundry endpoint | `bot_mainnet` in `contracts/foundry.toml` |
| Deploy guard | Requires `ALLOW_MAINNET_DEPLOYMENT=true`; refused otherwise |
| Deployment status | **Not deployed. Not to be deployed without independent review and BOT Chain's go-ahead.** |

The guard was verified: without the flag the script reverts with
`MAINNET DEPLOYMENT BLOCKED`; with the flag on a simulated node the dry run proceeds
but no transaction was broadcast (`docs/TESTNET_EVIDENCE.md`).

## 17. Deployment requirements

- Node/Foundry toolchain (Forge 1.5.x used here) and pnpm for OpenZeppelin.
- A funded deployer key (testnet first). Keys are supplied only via environment and are
  never committed; no key material exists in the repository.
- Owner/fee-recipient addresses (default to deployer if unset).
- Explorer verification endpoint/API flavour confirmed for the target chain.
- Post-deployment: record chain id, contract address, deployment tx/block, compiler
  settings; set the frontend per-chain vars (address + deploy block).
- Full procedure: `docs/DEPLOYMENT_RUNBOOK.md`.

## 18. Frontend requirements

- `NEXT_PUBLIC_CHAIN_ID=968`, default is already 968.
- `NEXT_PUBLIC_ESCROW_ADDRESS_968` = deployed address; `NEXT_PUBLIC_DEPLOY_BLOCK_968` =
  deployment block.
- `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` optional (injected wallets work without it).
- The frontend fails closed: mainnet is disabled unless
  `NEXT_PUBLIC_ALLOW_MAINNET=true`; writes are blocked unless
  `connectedChainId === selectedChainId`; an unset address makes the UI read-only.
- Display requirements already implemented: network, TESTNET/MAINNET + UNAUDITED
  status, contract address, connected wallet, roles, milestone state, escrow value,
  fee, transaction lifecycle, explorer links.

## 19. Indexing requirements

- Default: bounded chunked direct-RPC log scan from the deploy block (no infra).
- Production: HTTP indexer implementing the chain/contract-scoped API in
  `docs/INDEXING.md`; event identity `(chainId, contractAddress, txHash, logIndex)`;
  idempotent ingestion; confirmed-block checkpoints; reorg reconciliation.
- BOT Chain finality/confirmation depth to be confirmed (§20).

## 20. Unresolved questions for BOT Chain engineers

1. **EVM hardfork support**: the contract is compiled with solc 0.8.26 (default
   `cancun` EVM target). Does BOT Chain (968 and 677) support Cancun opcodes
   (`MCOPY`, `TSTORE`, blob-related opcodes not used but emitted by toolchain
   metadata)? If not, we will rebuild with `evm_version = "paris"` and re-verify.
2. **Finality/confirmation depth**: recommended `confirmations` for the indexer and
   frontend log scan on each chain.
3. **Faucet**: official Bohr testnet faucet (and any rate limits) so a public testnet
   deployment can be funded without manufacturing credentials.
4. **Explorer verification**: is `scan.bohr.life` Blockscout (for
   `--verifier blockscout --verifier-url https://scan.bohr.life/api/`), and does it
   need an API key?
5. **RPC limits**: `eth_getLogs` range cap, rate limits, and whether a dedicated
   endpoint is offered for indexers.
6. **Canonical test tokens**: any official BOT-chain test ERC-20 to exercise the
   ERC-20 path in public testing.
7. **Native symbol/decimals confirmation**: BOT, 18 decimals (assumed from published
   docs; confirm).
8. **Wallet support**: recommended wallet configuration/chain parameters for
   RainbowKit/wagmi users on Bohr.
9. **Contract standards expectations**: any BOT Chain-specific registry, verifier
   lifecycle, or ecosystem contract conventions the escrow should follow.
10. **677 go-live process**: what BOT Chain expects before a third-party contract is
    considered for mainnet ecosystem support.

## 21. Mainnet-readiness gates

None of the following are satisfied today. This list is the gate, not a claim:

- [ ] Independent security review with all high/medium findings resolved.
- [ ] Public testnet deployment with an operational runbook (deploy/verify/monitor).
- [ ] Indexer service running with reorg monitoring and alerting.
- [ ] Frontend deployed with mainnet disabled by default and an explicit opt-in build.
- [ ] Multi-sig ownership for `owner` and `feeRecipient`; documented key custody.
- [ ] Incident process: pause authority, communications, and (given
      non-upgradeability) a migration plan.
- [ ] Confirmed compatibility with BOT Chain EVM version and finality model.
- [ ] Bug-bounty or equivalent review window.
- [ ] BOT Chain engineering sign-off.
