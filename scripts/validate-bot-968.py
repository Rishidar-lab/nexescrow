#!/usr/bin/env python3
"""
Live/semi-live end-to-end validation harness for NexEscrow on BOT Chain Bohr
testnet (chain id 968).

Flow: deploy (or reuse an existing deployment manifest) -> create agreement ->
fund -> approve milestones -> create second agreement -> fund -> dispute ->
arbiter resolve -> balance snapshots -> event retrieval -> event-derived state
compared with direct contract reads -> conservation checks -> report.

Hard safety properties:
  - refuses to run on any chain other than 968;
  - never targets BOT mainnet (677);
  - never prints private keys;
  - uses only native test funds supplied by the operator's keys.

Evidence written to the evidence directory:
  deployment.json, transactions.json, balances-before.json, balances-after.json,
  events.json, direct-state.json, lifecycle-report.md

Usage:
  export PRIVATE_KEY=... SELLER_KEY=... ARBITER_KEY=...
  python3 scripts/validate-bot-968.py --rpc-url https://rpc.bohr.life \
      --evidence-dir docs/evidence/bot-968 --use-existing 0x<deployed>

All three keys are required from the environment; this harness never contains or
prints key material. Local validation against `anvil --chain-id 968` works the same
way (supply the Anvil keys via the environment yourself if you need them).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone

EXPECTED_CHAIN_ID = 968
NATIVE = "0x0000000000000000000000000000000000000000"
WAD = 10**18


def iso_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def hex_to_int(value) -> int:
    return int(value, 16) if isinstance(value, str) and value.startswith("0x") else int(value)


class CommandError(RuntimeError):
    pass


def sh(args: list[str], retries: int = 0, retry_delay: float = 2.0, check: bool = True) -> subprocess.CompletedProcess:
    last = None
    for attempt in range(retries + 1):
        result = subprocess.run(args, capture_output=True, text=True)
        if result.returncode == 0:
            return result
        last = result
        if attempt < retries:
            time.sleep(retry_delay)
    if check:
        raise CommandError(
            f"command failed ({last.returncode}): {' '.join(args[:4])} ...\n"
            f"stdout: {last.stdout[-1500:]}\nstderr: {last.stderr[-1500:]}"
        )
    return last


class Chain:
    def __init__(self, rpc_url: str):
        self.rpc_url = rpc_url

    def chain_id(self) -> int:
        return int(sh(["cast", "chain-id", "--rpc-url", self.rpc_url], retries=2).stdout.strip())

    def latest_block(self) -> int:
        return int(sh(["cast", "block-number", "--rpc-url", self.rpc_url], retries=2).stdout.strip())

    def balance_wei(self, address: str) -> int:
        return int(sh(["cast", "balance", address, "--rpc-url", self.rpc_url], retries=2).stdout.strip())

    def call(self, address: str, signature: str, *args: str) -> str:
        return sh(["cast", "call", address, signature, *args, "--rpc-url", self.rpc_url], retries=2).stdout.strip()

    def send(self, key: str, address: str, signature: str, *args: str, value_wei: int | None = None) -> dict:
        cmd = ["cast", "send", address, signature, *args, "--rpc-url", self.rpc_url,
               "--private-key", key, "--json"]
        if value_wei is not None:
            cmd += ["--value", str(value_wei)]
        result = sh(cmd)
        return json.loads(result.stdout)

    def rpc(self, method: str, params: list):
        cmd = ["cast", "rpc", method, *[json.dumps(param) for param in params], "--rpc-url", self.rpc_url]
        return json.loads(sh(cmd, retries=2).stdout)

    def tx_receipt(self, tx_hash: str) -> dict:
        return json.loads(sh(["cast", "receipt", tx_hash, "--rpc-url", self.rpc_url, "--json"], retries=2).stdout)


def address_of(key: str) -> str:
    return sh(["cast", "wallet", "address", "--private-key", key]).stdout.strip()


def keccak(signature: str) -> str:
    return sh(["cast", "keccak", signature]).stdout.strip()


def parse_agreement(text: str) -> dict:
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if len(lines) < 11:
        raise CommandError(f"unexpected agreements() output: {text!r}")
    return {
        "buyer": lines[0],
        "seller": lines[1],
        "arbiter": lines[2],
        "token": lines[3],
        "totalAmount": int(re.match(r"^(\d+)", lines[4]).group(1)),
        "feeBps": int(re.match(r"^(\d+)", lines[5]).group(1)),
        "status": int(re.match(r"^(\d+)", lines[6]).group(1)),
        "milestoneCount": int(re.match(r"^(\d+)", lines[9]).group(1)),
        "nextMilestone": int(re.match(r"^(\d+)", lines[10]).group(1)),
    }


def parse_milestones(text: str) -> list[dict]:
    pairs = re.findall(r"\((\d+)[^,)]*,\s*(\d+)\)", text)
    return [{"amount": int(amount), "status": int(status)} for amount, status in pairs]


def first_int(text: str) -> int:
    match = re.search(r"(\d+)", text)
    if not match:
        raise CommandError(f"no integer in output: {text!r}")
    return int(match.group(1))


def write_json(path: str, payload) -> None:
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rpc-url", default=os.environ.get("BOT_968_RPC_URL", "https://rpc.bohr.life"))
    parser.add_argument("--evidence-dir", default="docs/evidence/bot-968")
    parser.add_argument("--use-existing", default=None, help="existing deployed address (skips the deploy step)")
    args = parser.parse_args()

    rpc_url = args.rpc_url
    evidence_dir = os.path.abspath(args.evidence_dir)
    os.makedirs(evidence_dir, exist_ok=True)
    live = "rpc.bohr.life" in rpc_url
    started_at = iso_now()

    chain = Chain(rpc_url)

    # --- chain guard ---------------------------------------------------------
    chain_id = chain.chain_id()
    if chain_id != EXPECTED_CHAIN_ID:
        raise SystemExit(f"ABORT: chain id {chain_id} != {EXPECTED_CHAIN_ID}; this harness only runs on BOT Chain Bohr testnet.")

    # --- keys ----------------------------------------------------------------
    def key_from_env(name: str) -> str:
        value = os.environ.get(name, "").strip()
        if not value:
            raise SystemExit(f"ABORT: {name} is not set (operator credentials required; keys are never printed).")
        return value

    buyer_key = key_from_env("PRIVATE_KEY")
    seller_key = key_from_env("SELLER_KEY")
    arbiter_key = key_from_env("ARBITER_KEY")
    buyer = address_of(buyer_key)
    seller = address_of(seller_key)
    arbiter = address_of(arbiter_key)

    print(f"Network: chain {chain_id} ({'live BOT Bohr' if live else 'local 968'}) rpc={rpc_url}")
    print(f"Buyer/deployer: {buyer}\nSeller: {seller}\nArbiter: {arbiter}")

    # --- deployment step -----------------------------------------------------
    deployment_manifest_path = os.path.join(evidence_dir, "deployment.json")
    if args.use_existing:
        escrow = args.use_existing
        if not os.path.exists(deployment_manifest_path):
            raise SystemExit(f"ABORT: --use-existing given but {deployment_manifest_path} does not exist")
        code = sh(["cast", "code", escrow, "--rpc-url", rpc_url], retries=2).stdout.strip()
        if len(code) <= 2:
            raise SystemExit(f"ABORT: no contract code at {escrow} on chain {chain_id}")
        with open(deployment_manifest_path) as handle:
            deployment = json.load(handle)
        if deployment.get("address", "").lower() != escrow.lower():
            raise SystemExit("ABORT: manifest address does not match --use-existing")
        deployment_note = "pre-existing deployment manifest (deployed by scripts/deploy-bot-968.sh)"
    else:
        confirm = os.environ.get("CONFIRM_BOT_968_DEPLOY", "")
        if confirm != "BOT-968":
            raise SystemExit("ABORT: set CONFIRM_BOT_968_DEPLOY=BOT-968 to deploy")
        env = os.environ.copy()
        env["CONFIRM_BOT_968_DEPLOY"] = "BOT-968"
        wrapper = os.path.join(os.path.dirname(os.path.abspath(__file__)), "deploy-bot-968.sh")
        result = subprocess.run(["bash", wrapper, deployment_manifest_path], env=env, text=True)
        if result.returncode != 0:
            raise SystemExit("ABORT: deployment wrapper failed")
        with open(deployment_manifest_path) as handle:
            deployment = json.load(handle)
        escrow = deployment["address"]
        deployment_note = "deployed during this harness run"

    print(f"Escrow: {escrow} ({deployment_note})")

    # --- snapshots before ----------------------------------------------------
    def snapshot_balances() -> dict:
        return {
            "capturedAt": iso_now(),
            "chainId": chain_id,
            "escrow": {"address": escrow, "nativeWei": str(chain.balance_wei(escrow))},
            "buyer": {"address": buyer, "nativeWei": str(chain.balance_wei(buyer))},
            "seller": {"address": seller, "nativeWei": str(chain.balance_wei(seller))},
            "arbiter": {"address": arbiter, "nativeWei": str(chain.balance_wei(arbiter))},
        }

    balances_before = snapshot_balances()
    write_json(os.path.join(evidence_dir, "balances-before.json"), balances_before)

    transactions: list[dict] = []
    checks: list[dict] = []

    def record(step: str, receipt: dict, extra: dict | None = None) -> None:
        entry = {
            "step": step,
            "transactionHash": receipt.get("transactionHash"),
            "blockNumber": hex_to_int(receipt.get("blockNumber")) if receipt.get("blockNumber") else None,
            "gasUsed": hex_to_int(receipt.get("gasUsed")) if receipt.get("gasUsed") else None,
            "status": hex_to_int(receipt.get("status")) if receipt.get("status") else None,
        }
        if extra:
            entry.update(extra)
        transactions.append(entry)

    def check(name: str, ok: bool, detail: str) -> None:
        checks.append({"name": name, "ok": bool(ok), "detail": detail})
        print(f"  [{'PASS' if ok else 'FAIL'}] {name}: {detail}")

    # --- agreement A: two milestones, fully approved -------------------------
    id_a = first_int(chain.call(escrow, "nextAgreementId()(uint256)"))
    m_amount = 5 * 10**16  # 0.05 BOT
    receipt = chain.send(
        buyer_key, escrow, "createAgreement(address,address,address,uint128[],uint40)",
        seller, arbiter, NATIVE, f"[{m_amount},{m_amount}]", "0",
    )
    record("createAgreement(A)", receipt, {"agreementId": id_a})
    receipt = chain.send(buyer_key, escrow, "fund(uint256)", str(id_a), value_wei=2 * m_amount)
    record("fund(A)", receipt, {"agreementId": id_a, "valueWei": str(2 * m_amount)})
    receipt = chain.send(buyer_key, escrow, "approveMilestone(uint256)", str(id_a))
    record("approveMilestone(A,0)", receipt, {"agreementId": id_a})
    receipt = chain.send(buyer_key, escrow, "approveMilestone(uint256)", str(id_a))
    record("approveMilestone(A,1)", receipt, {"agreementId": id_a})

    # --- agreement B: single milestone, disputed and resolved ----------------
    id_b = first_int(chain.call(escrow, "nextAgreementId()(uint256)"))
    b_amount = 10**17  # 0.1 BOT
    receipt = chain.send(
        buyer_key, escrow, "createAgreement(address,address,address,uint128[],uint40)",
        seller, arbiter, NATIVE, f"[{b_amount}]", "0",
    )
    record("createAgreement(B)", receipt, {"agreementId": id_b})
    receipt = chain.send(buyer_key, escrow, "fund(uint256)", str(id_b), value_wei=b_amount)
    record("fund(B)", receipt, {"agreementId": id_b, "valueWei": str(b_amount)})
    receipt = chain.send(seller_key, escrow, "raiseDispute(uint256)", str(id_b))
    record("raiseDispute(B,seller)", receipt, {"agreementId": id_b})
    receipt = chain.send(arbiter_key, escrow, "resolveDispute(uint256,uint16)", str(id_b), "6000")
    record("resolveDispute(B,6000)", receipt, {"agreementId": id_b})

    balances_after = snapshot_balances()
    write_json(os.path.join(evidence_dir, "balances-after.json"), balances_after)
    write_json(os.path.join(evidence_dir, "transactions.json"), {"chainId": chain_id, "transactions": transactions})

    # --- direct contract reads ----------------------------------------------
    direct = {"chainId": chain_id, "escrow": escrow, "agreements": {}, "accruedFeesNative": None, "escrowBalanceWei": None}
    for label, agreement_id in (("A", id_a), ("B", id_b)):
        agreement = parse_agreement(chain.call(escrow, "agreements(uint256)(address,address,address,address,uint128,uint16,uint8,uint40,uint40,uint8,uint8)", str(agreement_id)))
        milestones = parse_milestones(chain.call(escrow, "getMilestones(uint256)((uint128,uint8)[])", str(agreement_id)))
        direct["agreements"][label] = {"id": agreement_id, **agreement, "milestones": milestones}
    direct["accruedFeesNative"] = str(first_int(chain.call(escrow, "accruedFees(address)(uint256)", NATIVE)))
    direct["escrowBalanceWei"] = str(chain.balance_wei(escrow))
    write_json(os.path.join(evidence_dir, "direct-state.json"), direct)

    # --- events --------------------------------------------------------------
    latest = chain.latest_block()
    logs = chain.rpc("eth_getLogs", [{"address": escrow, "fromBlock": "0x0", "toBlock": "latest"}])
    events_payload = {
        "chainId": chain_id,
        "address": escrow,
        "fromBlock": 0,
        "toBlock": latest,
        "retrievedAt": iso_now(),
        "count": len(logs),
        "logs": logs,
    }
    write_json(os.path.join(evidence_dir, "events.json"), events_payload)

    topics = {
        "AgreementCreated": keccak("AgreementCreated(uint256,address,address,address,address,uint128,uint16,uint40,uint128[])"),
        "Funded": keccak("Funded(uint256)"),
        "MilestoneReleased": keccak("MilestoneReleased(uint256,uint256,uint128,uint128)"),
        "DisputeRaised": keccak("DisputeRaised(uint256,uint256,address)"),
        "DisputeResolved": keccak("DisputeResolved(uint256,uint256,uint16,uint128,uint128,uint128)"),
        "AgreementCompleted": keccak("AgreementCompleted(uint256)"),
    }

    def topic_int(topic: str) -> int:
        return int(topic, 16)

    def words(data_hex: str) -> list[int]:
        raw = data_hex[2:] if data_hex.startswith("0x") else data_hex
        return [int(raw[i : i + 64], 16) for i in range(0, len(raw), 64)]

    by_name: dict[str, list[dict]] = {name: [] for name in topics}
    for log in logs:
        log_topics = log.get("topics", [])
        for name, topic in topics.items():
            if log_topics and log_topics[0] == topic:
                by_name[name].append(log)
                break

    created_ids = sorted(topic_int(log["topics"][1]) for log in by_name["AgreementCreated"])
    funded_ids = sorted(topic_int(log["topics"][1]) for log in by_name["Funded"])
    completed_ids = sorted(topic_int(log["topics"][1]) for log in by_name["AgreementCompleted"])
    releases_a = [
        {"index": topic_int(log["topics"][2]), **dict(zip(("amount", "fee"), words(log["data"])))}
        for log in by_name["MilestoneReleased"]
        if topic_int(log["topics"][1]) == id_a
    ]
    dispute_raised_b = [log for log in by_name["DisputeRaised"] if topic_int(log["topics"][1]) == id_b]
    dispute_resolved_b = [
        {"index": topic_int(log["topics"][2]), **dict(zip(("buyerBps", "buyerAmount", "sellerAmount", "fee"), words(log["data"])))}
        for log in by_name["DisputeResolved"]
        if topic_int(log["topics"][1]) == id_b
    ]

    # --- verification --------------------------------------------------------
    check("chain id is 968", chain_id == EXPECTED_CHAIN_ID, f"chain {chain_id}")
    check("deployment has code", len(sh(["cast", "code", escrow, "--rpc-url", rpc_url], retries=2).stdout.strip()) > 2, f"{escrow}")
    check("AgreementCreated count == 2", len(created_ids) == 2, f"ids {created_ids}")
    expected_ids = sorted([id_a, id_b])
    check("created ids match direct reads", created_ids == expected_ids, f"events {created_ids} vs direct {expected_ids}")
    check("Funded events for both", sorted(funded_ids) == expected_ids, f"funded {funded_ids}")
    check("AgreementCompleted for both", sorted(completed_ids) == expected_ids, f"completed {completed_ids}")

    a = direct["agreements"]["A"]
    b = direct["agreements"]["B"]
    check("A direct status Completed", a["status"] == 2, f"status {a['status']}, next {a['nextMilestone']}/{a['milestoneCount']}")
    check("A direct nextMilestone == 2", a["nextMilestone"] == 2, f"next {a['nextMilestone']}")
    check("A milestones both Released",
          all(m["status"] == 1 for m in a["milestones"]),
          f"statuses {[m['status'] for m in a['milestones']]}")
    check("A two MilestoneReleased events", len(releases_a) == 2, f"{releases_a}")
    check("A released indices {0,1}", sorted(r["index"] for r in releases_a) == [0, 1], f"indices {[r['index'] for r in releases_a]}")
    check("A released gross == total",
          sum(r["amount"] for r in releases_a) == a["totalAmount"],
          f"sum {sum(r['amount'] for r in releases_a)} == total {a['totalAmount']}")

    check("B direct status Completed", b["status"] == 2, f"status {b['status']}, next {b['nextMilestone']}/{b['milestoneCount']}")
    check("B direct nextMilestone == 1", b["nextMilestone"] == 1, f"next {b['nextMilestone']}")
    check("B milestone Resolved", b["milestones"][0]["status"] == 3, f"status {b['milestones'][0]['status']}")
    check("B DisputeRaised by seller",
          len(dispute_raised_b) == 1 and dispute_raised_b[0]["topics"][3].lower().endswith(seller[2:].lower()),
          f"raisedBy topic {dispute_raised_b[0]['topics'][3] if dispute_raised_b else None}")
    dr = dispute_resolved_b[0] if dispute_resolved_b else None
    expected_buyer = b_amount * 6000 // 10_000
    expected_gross = b_amount - expected_buyer
    expected_fee = expected_gross * a["feeBps"] // 10_000
    expected_seller = expected_gross - expected_fee
    check("B one DisputeResolved", len(dispute_resolved_b) == 1, f"{dispute_resolved_b}")
    if dr:
        check("B dispute buyerAmount matches floor(bps)", dr["buyerAmount"] == expected_buyer,
              f"event {dr['buyerAmount']} expected {expected_buyer}")
        check("B dispute sellerAmount matches fee math", dr["sellerAmount"] == expected_seller,
              f"event {dr['sellerAmount']} expected {expected_seller}")
        check("B dispute fee matches fee math", dr["fee"] == expected_fee,
              f"event {dr['fee']} expected {expected_fee}")

    total_fees = sum(r["fee"] for r in releases_a) + (dr["fee"] if dr else 0)
    check("accruedFees == event-derived fees", int(direct["accruedFeesNative"]) == total_fees,
          f"direct {direct['accruedFeesNative']} vs events {total_fees}")
    check("escrow balance == accrued fees (no principal left)", int(direct["escrowBalanceWei"]) == total_fees,
          f"escrow {direct['escrowBalanceWei']} vs fees {total_fees}")

    gross_b = (dr["buyerAmount"] + dr["sellerAmount"] + dr["fee"]) if dr else None
    conservation_ok = (
        dr is not None
        and sum(r["amount"] for r in releases_a) + gross_b == a["totalAmount"] + b["totalAmount"]
    )
    check("conservation: released + dispute gross == funded total", conservation_ok,
          f"{sum(r['amount'] for r in releases_a)} + {gross_b} == {a['totalAmount'] + b['totalAmount']}")

    # --- report --------------------------------------------------------------
    passed = sum(1 for c in checks if c["ok"])
    failed = [c for c in checks if not c["ok"]]
    report = [
        "# BOT Chain Bohr (968) Live Validation Report",
        "",
        f"- Generated: {started_at} -> {iso_now()} (UTC)",
        f"- RPC: `{rpc_url}` ({'LIVE BOT BOHR' if live else 'local simulated 968'})",
        f"- Chain id: {chain_id}",
        f"- Contract: `{escrow}`",
        f"- Deployment: {deployment_note}",
        f"- Buyer: `{buyer}`  Seller: `{seller}`  Arbiter: `{arbiter}`",
        "",
        "## Transactions",
        "",
        "| Step | Tx hash | Block | Gas used | Status |",
        "|---|---|---|---|---|",
    ]
    for tx in transactions:
        report.append(f"| {tx['step']} | `{tx['transactionHash']}` | {tx['blockNumber']} | {tx['gasUsed']} | {tx['status']} |")
    report += [
        "",
        "## Balances (native wei)",
        "",
        "| Account | Before | After |",
        "|---|---|---|",
        f"| Buyer | {balances_before['buyer']['nativeWei']} | {balances_after['buyer']['nativeWei']} |",
        f"| Seller | {balances_before['seller']['nativeWei']} | {balances_after['seller']['nativeWei']} |",
        f"| Arbiter | {balances_before['arbiter']['nativeWei']} | {balances_after['arbiter']['nativeWei']} |",
        f"| Escrow | {balances_before['escrow']['nativeWei']} | {balances_after['escrow']['nativeWei']} |",
        "",
        "Balance deltas include gas paid by each signer; conservation is asserted on",
        "event amounts and direct contract state, which are gas-independent.",
        "",
        "## Event-derived state vs direct reads",
        "",
        f"- Agreement A (id {id_a}): {len(releases_a)} `MilestoneReleased` events; direct status Completed,",
        f"  cursor {a['nextMilestone']}/{a['milestoneCount']}; released gross {sum(r['amount'] for r in releases_a)} == total {a['totalAmount']}.",
        f"- Agreement B (id {id_b}): `DisputeRaised` by seller, `DisputeResolved(buyerBps={dr['buyerBps'] if dr else 'n/a'})`;",
        f"  direct status Completed, cursor {b['nextMilestone']}/{b['milestoneCount']}; milestone Resolved.",
        f"- Accrued fees: direct {direct['accruedFeesNative']} == event-derived {total_fees}; escrow balance {direct['escrowBalanceWei']}.",
        f"- Conservation: released gross + dispute gross == funded total ({a['totalAmount'] + b['totalAmount']}).",
        "",
        "## Checks",
        "",
        "| Check | Result | Detail |",
        "|---|---|---|",
    ]
    for c in checks:
        report.append(f"| {c['name']} | {'PASS' if c['ok'] else 'FAIL'} | {c['detail']} |")
    report += [
        "",
        f"**Summary: {passed}/{len(checks)} checks passed.**",
        "",
        "Notes:",
        "- The contract is **unaudited**; this is a testnet validation, not an audit or a production statement.",
        "- Any funds used are BOT Bohr testnet funds only.",
    ]
    with open(os.path.join(evidence_dir, "lifecycle-report.md"), "w", encoding="utf-8") as handle:
        handle.write("\n".join(report) + "\n")

    print(f"\nResult: {passed}/{len(checks)} checks passed; evidence in {evidence_dir}")
    if failed:
        print("FAILED CHECKS:")
        for c in failed:
            print(f" - {c['name']}: {c['detail']}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
