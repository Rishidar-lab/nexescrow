# Fresh Bohr 968 Testnet Run — BLOCKED

- **Recorded (UTC):** 2026-10-14T02:09:00Z
- **Branch:** `feat/botchain-integration`
- **Commit:** `7d1832b5f09845703938e8eb10cc049956e8ede3`
- **Target:** BOT Chain Bohr **testnet** (chain id 968), RPC `https://rpc.bohr.life`
- **Result:** **NOT PERFORMED — BLOCKED**

## Outcome

A fresh end-to-end validation run on BOT Chain Bohr testnet 968 was **not performed**
in this execution. No new transactions were sent, no new contract was deployed, and
no new transaction hashes exist. Nothing in this document is evidence of a
validation run.

**No evidence was fabricated.** The previously validated 968 deployment
(`0x6448668ae9cbbc41617c2bd5e4f29279320a2700`) remains the only live 968 evidence in
this repository, and it was fully re-verified against chain during this execution —
see `docs/evidence/FINAL-BUILDER-VALIDATION.md`.

## Blocker (non-secret)

A fresh run requires three funded BOT Bohr testnet signing keys, supplied by the
operator through the environment. None are available in this execution environment:

| Requirement | State | How checked |
|---|---|---|
| `PRIVATE_KEY` (deployer / buyer) | not set | environment probe |
| `SELLER_KEY` (seller) | not set | environment probe |
| `ARBITER_KEY` (arbiter) | not set | environment probe |
| `contracts/.env` or `contracts/.env.local` | absent | filesystem check |
| Foundry keystore (`~/.foundry/*.json`) | no keystore present | filesystem check |

Key **values** were never read, printed, or searched for. Only the presence of the
environment variables and of key-store files was checked.

Both required harnesses read keys exclusively from the process environment and have
no on-disk fallback:

- `scripts/deploy-bot-968.sh` — requires `PRIVATE_KEY` and `CONFIRM_BOT_968_DEPLOY=BOT-968`
- `scripts/validate-bot-968.py` — requires `PRIVATE_KEY`, `SELLER_KEY`, `ARBITER_KEY`

No key material is committed to this repository, by design; `contracts/.env.example`
contains placeholders only.

## Why this is not worked around

Fabricating a "fresh run" from the 2026-10-08 transaction hashes, or relabelling
historical hashes as new, would be evidence falsification. The correct outcome of an
unavailable signer is a recorded blocker, not a manufactured artifact.

## What IS proven current

The blocking condition is **signer availability only**. Everything else required for
a 968 run is verified working in this execution:

- The Bohr 968 RPC is reachable and reports chain id **968** (read-only probe).
- The deployed 968 instance is live, has code, and all 8 lifecycle receipts plus the
  deployment receipt are confirmed `status=1` on chain.
- `scripts/verify-bot-968-evidence.py --rpc-url https://rpc.bohr.life` completes with
  **34/34 checks passed, 0 failed**.
- The deploy wrapper's chain guard is proven by test: `DeployPolicy.requireBotTestnetOnly`
  reverts for every chain id except 968, including 677
  (`test_Wiring_BOTScript_RefusesMainnet677`, `testBOT_Policy_RejectsEveryChainExcept968`).

## To unblock

Supply three funded **testnet** keys and explicit deploy intent, then run:

```bash
read -rsp "Bohr deployer/buyer private key: " PRIVATE_KEY && printf '\n'
read -rsp "Bohr seller private key: " SELLER_KEY && printf '\n'
read -rsp "Bohr arbiter private key: " ARBITER_KEY && printf '\n'
export PRIVATE_KEY SELLER_KEY ARBITER_KEY
export CONFIRM_BOT_968_DEPLOY=BOT-968

python3 scripts/validate-bot-968.py \
  --rpc-url https://rpc.bohr.life \
  --evidence-dir docs/evidence/bot-968-<YYYYMMDD>

# Clear signing material from the process environment after the run.
unset PRIVATE_KEY SELLER_KEY ARBITER_KEY
```

This harness refuses to run on any chain other than 968 and never targets BOT
mainnet 677. The silent prompts keep key values out of terminal output and shell
history. Use minimal testnet value only.

## Status

```
FRESH BOHR 968 RUN: BLOCKED — operator testnet signing keys unavailable
NEW TRANSACTIONS:   NONE
NEW EVIDENCE:       NONE (nothing fabricated)
BUILDER IMPACT:     none — all builder-controlled validation passed independently
```
