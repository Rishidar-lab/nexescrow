#!/usr/bin/env python3
"""
Verifier for the committed BOT Bohr (968) validation evidence.

Local mode (default) re-derives the accounting from the raw event records and
cross-checks every committed JSON artifact. Optional --rpc-url mode performs
READ-ONLY on-chain cross-checks (receipts, state reads, one bounded eth_getLogs
re-query). It never sends transactions.

Usage:
  python3 scripts/verify-bot-968-evidence.py
  python3 scripts/verify-bot-968-evidence.py --rpc-url https://rpc.bohr.life
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys

EVIDENCE = "docs/evidence/bot-968"
NATIVE = "0x0000000000000000000000000000000000000000"


def sh(args: list[str]) -> str:
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"command failed: {' '.join(args[:4])}...\n{result.stderr[-800:]}")
    return result.stdout.strip()


def keccak(signature: str) -> str:
    return sh(["cast", "keccak", signature])


def words(data: str) -> list[int]:
    raw = data[2:] if data.startswith("0x") else data
    return [int(raw[i : i + 64], 16) for i in range(0, len(raw), 64)]


def first_int(text: str) -> int:
    match = re.search(r"(\d+)", text)
    if not match:
        raise RuntimeError(f"no integer in cast output: {text!r}")
    return int(match.group(1))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--rpc-url", default=None, help="optional read-only on-chain cross-check")
    parser.add_argument("--evidence-dir", default=EVIDENCE)
    args = parser.parse_args()

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    evidence = os.path.join(root, args.evidence_dir)
    failures: list[str] = []

    def check(name: str, ok: bool, detail: str = "") -> None:
        print(f"[{'PASS' if ok else 'FAIL'}] {name}" + (f" :: {detail}" if detail else ""))
        if not ok:
            failures.append(name)

    load = lambda name: json.load(open(os.path.join(evidence, name)))  # noqa: E731

    deployment = load("deployment.json")
    registry = load("deployments-registry.json")
    direct = load("direct-state.json")
    events = load("events.json")
    transactions = load("transactions.json")
    before = load("balances-before.json")
    after = load("balances-after.json")

    # ---- local consistency --------------------------------------------------
    check("deployment chainId == 968", deployment["chainId"] == 968, str(deployment["chainId"]))
    check("deployment address matches direct/events",
          deployment["address"].lower() == direct["escrow"].lower() == events["address"].lower(),
          deployment["address"])
    validated = [d for d in registry["deployments"] if d.get("verified")]
    check("registry has exactly one verified validated instance", len(validated) == 1)
    check("validated registry address matches deployment",
          validated and validated[0]["address"].lower() == deployment["address"].lower())
    check("deployment tx hash present", bool(re.match(r"^0x[0-9a-f]{64}$", deployment["transactionHash"])))

    # ---- re-derive accounting from raw events -------------------------------
    topic_signatures = {
        keccak("AgreementCreated(uint256,address,address,address,address,uint128,uint16,uint40,uint128[])"): "AgreementCreated",
        keccak("Funded(uint256)"): "Funded",
        keccak("MilestoneReleased(uint256,uint256,uint128,uint128)"): "MilestoneReleased",
        keccak("DisputeRaised(uint256,uint256,address)"): "DisputeRaised",
        keccak("DisputeResolved(uint256,uint256,uint16,uint128,uint128,uint128)"): "DisputeResolved",
        keccak("AgreementCompleted(uint256)"): "AgreementCompleted",
        # Emitted by the Ownable constructor, expected once at deployment.
        keccak("OwnershipTransferred(address,address)"): "OwnershipTransferred",
    }
    by_name: dict[str, list] = {name: [] for name in topic_signatures.values()}
    unknown = 0
    for log in events["logs"]:
        name = topic_signatures.get(log["topics"][0])
        if name:
            by_name[name].append(log)
        else:
            unknown += 1

    a_events = [log for log in by_name["MilestoneReleased"] if int(log["topics"][1], 16) == 0]
    b_disputes = [log for log in by_name["DisputeResolved"] if int(log["topics"][1], 16) == 1]
    released_gross = sum(words(log["data"])[0] for log in a_events)
    release_fees = sum(words(log["data"])[1] for log in a_events)
    dispute = words(b_disputes[0]["data"]) if b_disputes else None
    dispute_gross = sum(dispute[1:4]) if dispute else 0
    dispute_fee = dispute[3] if dispute else 0
    total_fees = release_fees + dispute_fee

    check("no unknown event topics", unknown == 0, f"unknown={unknown}")
    check("AgreementCreated == 2", len(by_name["AgreementCreated"]) == 2)
    check("Funded == 2", len(by_name["Funded"]) == 2)
    check("AgreementCompleted == 2", len(by_name["AgreementCompleted"]) == 2)
    check("MilestoneReleased A == 2", len(a_events) == 2)
    check("DisputeRaised == 1 and DisputeResolved == 1",
          len(by_name["DisputeRaised"]) == 1 and len(b_disputes) == 1)
    check("released gross == 0.1 BOT", released_gross == 100_000_000_000_000_000, str(released_gross))
    check("dispute gross == 0.1 BOT", dispute_gross == 100_000_000_000_000_000, str(dispute_gross))
    check("dispute split 6000 bps exact",
          dispute is not None and dispute[0] == 6000 and dispute[1] == 60_000_000_000_000_000
          and dispute[2] == 39_600_000_000_000_000 and dispute[3] == 400_000_000_000_000)
    check("event-derived total fees == 0.0014 BOT (independent of prompt)",
          total_fees == 1_400_000_000_000_000, str(total_fees))
    check("accruedFees == event-derived fees",
          int(direct["accruedFeesNative"]) == total_fees, direct["accruedFeesNative"])
    check("escrow balance == accruedFees (zero principal loss)",
          int(direct["escrowBalanceWei"]) == total_fees == int(after["escrow"]["nativeWei"]))
    check("conservation: released gross + dispute gross == funded total",
          released_gross + dispute_gross == 200_000_000_000_000_000)
    check("direct agreement A terminal/cursor", direct["agreements"]["A"]["status"] == 2 and direct["agreements"]["A"]["nextMilestone"] == 2)
    check("direct agreement B terminal/cursor", direct["agreements"]["B"]["status"] == 2 and direct["agreements"]["B"]["nextMilestone"] == 1)

    # ---- lifecycle tx + balances --------------------------------------------
    txs = transactions["transactions"]
    check("8 lifecycle transactions", len(txs) == 8, str(len(txs)))
    check("all lifecycle txs status == 1", all(t["status"] == 1 for t in txs))
    check("unique tx hashes", len({t["transactionHash"] for t in txs}) == len(txs))
    check("ascending blocks", [t["blockNumber"] for t in txs] == sorted(t["blockNumber"] for t in txs))
    check("balances-before/after have chain 968",
          before["chainId"] == 968 and after["chainId"] == 968)
    check("seller + buyer refunds present in dispute (roles distinct)",
          len({direct["agreements"]["A"]["buyer"], direct["agreements"]["A"]["seller"],
               direct["agreements"]["A"]["arbiter"]}) == 3)

    # ---- optional on-chain cross-check (read-only) --------------------------
    if args.rpc_url:
        rpc = args.rpc_url
        check("rpc chainId == 968", sh(["cast", "chain-id", "--rpc-url", rpc]) == "968")
        code = sh(["cast", "code", deployment["address"], "--rpc-url", rpc])
        check("deployed bytecode hash matches manifest",
              sh(["cast", "keccak", code]) == deployment["bytecodeHash"])
        receipt = json.loads(sh(["cast", "receipt", deployment["transactionHash"], "--rpc-url", rpc, "--json"]))
        check("deployment receipt success at recorded block",
              int(receipt["status"], 16) == 1 and int(receipt["blockNumber"], 16) == deployment["blockNumber"],
              f"block {int(receipt['blockNumber'], 16)}")
        for tx in txs:
            r = json.loads(sh(["cast", "receipt", tx["transactionHash"], "--rpc-url", rpc, "--json"]))
            ok = int(r["status"], 16) == 1 and int(r["blockNumber"], 16) == tx["blockNumber"]
            if not ok:
                check(f"receipt {tx['step']}", False, tx["transactionHash"])
                break
        else:
            check("all lifecycle receipts re-confirmed on-chain", True)
        next_id = first_int(sh(["cast", "call", deployment["address"], "nextAgreementId()(uint256)", "--rpc-url", rpc]))
        check("nextAgreementId == 2 on-chain", next_id == 2, str(next_id))
        fees = first_int(sh(["cast", "call", deployment["address"], "accruedFees(address)(uint256)", NATIVE, "--rpc-url", rpc]))
        check("accruedFees matches on-chain", fees == total_fees, str(fees))
        bal = int(sh(["cast", "balance", deployment["address"], "--rpc-url", rpc]))
        check("escrow balance matches on-chain", bal == total_fees, str(bal))
        # One bounded re-query reproducing the recorded event block window.
        logs = json.loads(sh(["cast", "rpc", "eth_getLogs",
                              json.dumps({"address": deployment["address"],
                                          "fromBlock": "0x0",
                                          "toBlock": hex(events["toBlock"])}),
                              "--rpc-url", rpc]))
        recorded = {(log["transactionHash"].lower(), log["logIndex"]) for log in events["logs"]}
        live = {(log["transactionHash"].lower(), log["logIndex"]) for log in logs}
        check("re-queried event identity set matches committed events.json", recorded == live,
              f"recorded={len(recorded)} live={len(live)}")

    print()
    if failures:
        print(f"{len(failures)} check(s) FAILED: {failures}")
        return 1
    print("ALL EVIDENCE CHECKS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
