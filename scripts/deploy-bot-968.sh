#!/usr/bin/env bash
#
# Guarded BOT Chain Bohr testnet (chain 968) deployment for NexusEscrow.
#
#   - requires operator credentials (PRIVATE_KEY); never prints the key
#   - aborts unless chain id == 968 (never deploys to BOT mainnet 677)
#   - verifies deployer balance against the dry-run gas estimate
#   - requires explicit intent: CONFIRM_BOT_968_DEPLOY=BOT-968
#   - prints predicted contract address
#   - writes a deployment manifest with tx hash, address, block number,
#     gas used and runtime bytecode keccak256
#
# Usage:
#   export PRIVATE_KEY=...                      # burner testnet key
#   export CONFIRM_BOT_968_DEPLOY=BOT-968
#   scripts/deploy-bot-968.sh [manifest.json]
#
#   # local validation against anvil --chain-id 968:
#   BOT_968_RPC_URL=http://127.0.0.1:8602 scripts/deploy-bot-968.sh /tmp/deployment.json
#
set -euo pipefail

EXPECTED_CHAIN_ID=968
RPC_URL="${BOT_968_RPC_URL:-https://rpc.bohr.life}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTRACTS_DIR="$REPO_ROOT/contracts"
MANIFEST="${1:-$REPO_ROOT/docs/evidence/bot-968/deployment.json}"
EVIDENCE_DIR="$(dirname "$MANIFEST")"
SCRIPT="script/DeployNexusEscrowBOT.s.sol:DeployNexusEscrowBOT"
BROADCAST_ART="$CONTRACTS_DIR/broadcast/DeployNexusEscrowBOT.s.sol/968/run-latest.json"

fail() { printf 'ABORT: %s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*"; }

# --- preconditions -----------------------------------------------------------

[ -n "${PRIVATE_KEY:-}" ] || fail "PRIVATE_KEY is not set. Operator credentials are required (the key is never printed)."
[ "${CONFIRM_BOT_968_DEPLOY:-}" = "BOT-968" ] || fail "Refusing to deploy without explicit intent. Set CONFIRM_BOT_968_DEPLOY=BOT-968 for BOT Chain Bohr testnet (chain 968)."

for tool in forge cast jq python3; do
  command -v "$tool" >/dev/null 2>&1 || fail "required tool not found: $tool"
done
[ -f "$CONTRACTS_DIR/foundry.toml" ] || fail "contracts project not found at $CONTRACTS_DIR"

# --- chain guard (before anything else) --------------------------------------

CHAIN_ID="$(cast chain-id --rpc-url "$RPC_URL" 2>/dev/null)" || fail "cannot reach RPC $RPC_URL"
[ "$CHAIN_ID" = "$EXPECTED_CHAIN_ID" ] || fail "chain id $CHAIN_ID != $EXPECTED_CHAIN_ID. This script only deploys to BOT Chain Bohr testnet. BOT mainnet (677) is out of scope."

DEPLOYER="$(cast wallet address --private-key "$PRIVATE_KEY")" || fail "could not derive deployer address from PRIVATE_KEY"
BALANCE_WEI="$(cast balance "$DEPLOYER" --rpc-url "$RPC_URL")" || fail "could not read deployer balance"
[ "$BALANCE_WEI" != "0" ] || fail "deployer $DEPLOYER has zero balance on chain $CHAIN_ID"

OWNER="${ESCROW_OWNER:-$DEPLOYER}"
FEE_RECIPIENT="${ESCROW_FEE_RECIPIENT:-$DEPLOYER}"

note "Network:       BOT Chain Bohr testnet (chain $CHAIN_ID)"
note "RPC:           $RPC_URL"
note "Deployer:      $DEPLOYER"
note "Balance (wei): $BALANCE_WEI"
note "Owner:         $OWNER"
note "Fee recipient: $FEE_RECIPIENT"

PREDICTED="$(cast compute-address "$DEPLOYER" --rpc-url "$RPC_URL" 2>/dev/null | grep -oE '0x[0-9a-fA-F]{40}' | head -1 || true)"
[ -n "$PREDICTED" ] && note "Predicted contract address: $PREDICTED" || note "Predicted contract address: unavailable"

# --- dry run: gas estimate + balance sufficiency -----------------------------

mkdir -p "$EVIDENCE_DIR"
DRY_LOG="$EVIDENCE_DIR/deploy-968-dry-run.log"
note "Running dry run (no broadcast)..."
( cd "$CONTRACTS_DIR" && forge script "$SCRIPT" --rpc-url "$RPC_URL" -vv ) 2>&1 | tee "$DRY_LOG" >/dev/null

GAS_ESTIMATE="$(grep -oE 'Estimated total gas used for script: [0-9]+' "$DRY_LOG" | grep -oE '[0-9]+' | tail -1 || true)"
REQUIRED_ETH="$(grep -oE 'Estimated amount required: [0-9.]+' "$DRY_LOG" | grep -oE '[0-9.]+' | tail -1 || true)"
[ -n "$GAS_ESTIMATE" ] && note "Gas estimate:  $GAS_ESTIMATE"
if [ -n "$REQUIRED_ETH" ]; then
  REQUIRED_WEI="$(cast to-wei "$REQUIRED_ETH" ether 2>/dev/null || true)"
  note "Estimated cost: $REQUIRED_ETH native ($REQUIRED_WEI wei)"
  if [ -n "$REQUIRED_WEI" ]; then
    python3 - "$BALANCE_WEI" "$REQUIRED_WEI" <<'PY' || fail "deployer balance is below the estimated deployment cost"
import sys
if int(sys.argv[1]) < int(sys.argv[2]):
    print(f"balance {sys.argv[1]} wei < required {sys.argv[2]} wei", file=sys.stderr)
    sys.exit(1)
PY
    note "Balance check: OK (balance covers estimated cost)"
  fi
else
  note "Balance check: could not parse an estimate; deployer balance is non-zero (minimal check passed)"
fi

# --- broadcast ---------------------------------------------------------------

BROADCAST_LOG="$EVIDENCE_DIR/deploy-968-broadcast.log"
note "Broadcasting deployment..."
( cd "$CONTRACTS_DIR" && forge script "$SCRIPT" --rpc-url "$RPC_URL" --broadcast -vv ) 2>&1 | tee "$BROADCAST_LOG" >/dev/null

[ -f "$BROADCAST_ART" ] || fail "broadcast artifact not found at $BROADCAST_ART"

ADDRESS="$(jq -r '[.transactions[] | select(.transactionType=="CREATE")][-1].contractAddress' "$BROADCAST_ART")"
TX_HASH="$(jq -r '[.transactions[] | select(.transactionType=="CREATE")][-1].hash' "$BROADCAST_ART")"
[ -n "$ADDRESS" ] && [ "$ADDRESS" != "null" ] || fail "could not read contract address from broadcast artifact"
[ -n "$TX_HASH" ] && [ "$TX_HASH" != "null" ] || fail "could not read deployment tx hash from broadcast artifact"

RECEIPT_JSON="$(cast receipt "$TX_HASH" --rpc-url "$RPC_URL" --json)"
BLOCK_HEX="$(printf '%s' "$RECEIPT_JSON" | jq -r '.blockNumber')"
GAS_HEX="$(printf '%s' "$RECEIPT_JSON" | jq -r '.gasUsed')"
BLOCK_NUMBER="$(cast to-dec "$BLOCK_HEX" 2>/dev/null || printf '%s' "$BLOCK_HEX")"
GAS_USED="$(cast to-dec "$GAS_HEX" 2>/dev/null || printf '%s' "$GAS_HEX")"

CODE_HASH="$(cast keccak "$(cast code "$ADDRESS" --rpc-url "$RPC_URL")")"

if [ -n "$PREDICTED" ]; then
  ADDRESS_LC="$(printf '%s' "$ADDRESS" | tr '[:upper:]' '[:lower:]')"
  PREDICTED_LC="$(printf '%s' "$PREDICTED" | tr '[:upper:]' '[:lower:]')"
  [ "$ADDRESS_LC" = "$PREDICTED_LC" ] || note "WARNING: actual address differs from the pre-deploy prediction ($PREDICTED)"
fi

GIT_COMMIT="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
DEPLOYED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

python3 - "$MANIFEST" <<PY
import json, sys
manifest = {
    "chainId": $CHAIN_ID,
    "network": "BOT Chain Bohr Testnet",
    "rpcUrl": "$RPC_URL",
    "contract": "NexusEscrow",
    "address": "$ADDRESS",
    "transactionHash": "$TX_HASH",
    "blockNumber": int("$BLOCK_NUMBER"),
    "gasUsed": int("$GAS_USED"),
    "gasEstimate": int("${GAS_ESTIMATE:-0}") if "${GAS_ESTIMATE:-0}".isdigit() else None,
    "bytecodeHash": "$CODE_HASH",
    "deployer": "$DEPLOYER",
    "owner": "$OWNER",
    "feeRecipient": "$FEE_RECIPIENT",
    "compiler": {
        "solc": "0.8.26",
        "optimizer": True,
        "optimizerRuns": 200,
        "viaIR": True,
        "evmVersion": "cancun",
    },
    "gitCommit": "$GIT_COMMIT",
    "deployedAt": "$DEPLOYED_AT",
    "auditStatus": "UNAUDITED",
}
with open("$MANIFEST", "w") as fh:
    json.dump(manifest, fh, indent=2)
    fh.write("\n")
PY

note ""
note "Deployment complete."
note "Contract address: $ADDRESS"
note "Transaction:      $TX_HASH"
note "Block:            $BLOCK_NUMBER (gas used $GAS_USED)"
note "Bytecode hash:    $CODE_HASH"
note "Manifest:         $MANIFEST"
note "Reminder: UNAUDITED contract on a testnet. Do not claim production readiness."
