#!/usr/bin/env python3
"""
Read-only BOT Chain network-compatibility harness for NexEscrow.

This orchestrates the repository's existing RPC capability/range probes plus a
short head-stability observation. It never sends transactions. BOT mainnet
(chain 677) is opt-in for reads only and remains disabled for writes/deployment.

The resulting bundle is observational evidence only. It must not be interpreted
as a BOT Chain finality guarantee, retry policy, opcode/precompile guarantee,
security audit, or production-readiness approval.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import subprocess
import sys
from datetime import datetime, timezone
from urllib.parse import urlsplit

ROOT = pathlib.Path(__file__).resolve().parents[1]

CHAINS = {
    968: {
        "name": "bot-bohr-testnet",
        "rpc_url": "https://rpc.bohr.life",
        "log_address": "0x6448668ae9cbbc41617c2bd5e4f29279320a2700",
        "historical_block": 26178651,
        "receipt_tx": "0x4216d1e1eb33e296e3a3040baa723b507ce2da449d60e6ffe9456cecacf6da61",
    },
    677: {
        "name": "bot-mainnet",
        "rpc_url": "https://rpc.botchain.ai",
        "log_address": None,
        "historical_block": None,
        "receipt_tx": None,
    },
}

EVIDENCE_BOUNDARY = {
    "observational_only": True,
    "no_transactions": True,
    "no_deployment": True,
    "does_not_establish": [
        "BOT Chain finality guarantee",
        "BOT Chain retry/backoff policy",
        "BOT Chain opcode/precompile guarantee",
        "security audit",
        "production readiness",
        "ecosystem-support approval",
    ],
}


def iso_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def validate_public_rpc_url(value: str) -> str:
    parsed = urlsplit(value)
    if parsed.scheme != "https" or not parsed.netloc:
        raise ValueError("RPC URL must be an absolute https:// URL")
    if parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ValueError(
            "RPC URL must not contain credentials, query parameters, or fragments; "
            "the harness records the URL in evidence."
        )
    return value


def sha256_file(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def run_step(name: str, command: list[str], dry_run: bool) -> dict:
    if dry_run:
        return {"name": name, "command": command, "status": "planned", "exit_code": None}

    proc = subprocess.run(
        command,
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    return {
        "name": name,
        "command": command,
        "status": "passed" if proc.returncode == 0 else "failed",
        "exit_code": proc.returncode,
        "stdout_tail": proc.stdout[-4000:],
        "stderr_tail": proc.stderr[-4000:],
    }


def build_plan(args: argparse.Namespace) -> tuple[dict, list[tuple[str, list[str], pathlib.Path]]]:
    if args.chain_id not in CHAINS:
        raise ValueError(f"unsupported chain id: {args.chain_id}")
    if args.chain_id == 677 and not args.allow_mainnet_read:
        raise ValueError(
            "chain 677 is gated: pass --allow-mainnet-read for read-only observation; "
            "this flag never enables writes or deployment"
        )

    cfg = dict(CHAINS[args.chain_id])
    if args.rpc_url:
        cfg["rpc_url"] = validate_public_rpc_url(args.rpc_url)
    else:
        cfg["rpc_url"] = validate_public_rpc_url(cfg["rpc_url"])

    out_dir = pathlib.Path(args.out_dir)
    if not out_dir.is_absolute():
        out_dir = ROOT / out_dir

    capability = out_dir / f"{cfg['name']}-rpc-capability.json"
    range_cap = out_dir / f"{cfg['name']}-range-cap.json"
    head_stability = out_dir / f"{cfg['name']}-head-stability.json"

    capability_cmd = [
        sys.executable,
        str(ROOT / "scripts" / "probe-bot-rpc.py"),
        "--name",
        cfg["name"],
        "--rpc-url",
        cfg["rpc_url"],
        "--expected-chain-id",
        str(args.chain_id),
        "--max-range",
        str(args.max_range),
        "--max-results",
        str(args.max_results),
        "--out",
        str(capability),
    ]
    if cfg.get("log_address"):
        capability_cmd += ["--log-address", str(cfg["log_address"])]
    if cfg.get("historical_block") is not None:
        capability_cmd += ["--historical-block", str(cfg["historical_block"])]
    if cfg.get("receipt_tx"):
        capability_cmd += ["--receipt-tx", str(cfg["receipt_tx"])]

    steps: list[tuple[str, list[str], pathlib.Path]] = [
        ("rpc-capability", capability_cmd, capability)
    ]

    if not args.skip_range_cap:
        range_cmd = [
            sys.executable,
            str(ROOT / "scripts" / "probe-bot-rpc-range-cap.py"),
            "--name",
            cfg["name"],
            "--rpc-url",
            cfg["rpc_url"],
            "--spans",
            args.spans,
            "--out",
            str(range_cap),
        ]
        steps.append(("eth-getLogs-range-cap", range_cmd, range_cap))

    if args.include_execution_trace:
        if args.chain_id != 968 and not args.transactions:
            raise ValueError(
                "--include-execution-trace on chain 677 requires an explicit "
                "--transactions file from a controlled 677 exercise"
            )
        transactions = args.transactions or "docs/evidence/bot-968/transactions.json"
        trace_out = out_dir / f"{cfg['name']}-execution-trace.json"
        trace_cmd = [
            sys.executable,
            str(ROOT / "scripts" / "probe-cancun-execution.py"),
            "--rpc-url",
            cfg["rpc_url"],
            "--expected-chain-id",
            str(args.chain_id),
            "--transactions",
            transactions,
            "--out",
            str(trace_out),
        ]
        steps.append(("execution-trace-inventory", trace_cmd, trace_out))

    if not args.skip_head_stability:
        stability_cmd = [
            sys.executable,
            str(ROOT / "scripts" / "observe-bot-head-stability.py"),
            "--name",
            cfg["name"],
            "--rpc-url",
            cfg["rpc_url"],
            "--expected-chain-id",
            str(args.chain_id),
            "--samples",
            str(args.samples),
            "--interval-s",
            str(args.interval_s),
            "--depth",
            str(args.depth),
            "--out",
            str(head_stability),
        ]
        steps.append(("head-stability", stability_cmd, head_stability))

    metadata = {
        "schema_version": 1,
        "generated_at": iso_now(),
        "chain_id": args.chain_id,
        "network": cfg["name"],
        "rpc_url": cfg["rpc_url"],
        "read_only": True,
        "mainnet_read_opt_in": bool(args.allow_mainnet_read),
        "evidence_boundary": EVIDENCE_BOUNDARY,
        "parameters": {
            "max_range": args.max_range,
            "max_results": args.max_results,
            "range_spans": args.spans,
            "head_samples": args.samples,
            "head_interval_s": args.interval_s,
            "head_depth": args.depth,
        },
    }
    return metadata, steps


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--chain-id", type=int, choices=sorted(CHAINS), default=968)
    parser.add_argument("--rpc-url", default=None)
    parser.add_argument("--allow-mainnet-read", action="store_true")
    parser.add_argument(
        "--out-dir",
        default="docs/evidence/bot-network-compatibility",
        help="directory for generated evidence bundle",
    )
    parser.add_argument("--max-range", type=int, default=2_000)
    parser.add_argument("--max-results", type=int, default=10_000)
    parser.add_argument("--spans", default="500,1000,2000")
    parser.add_argument("--samples", type=int, default=6)
    parser.add_argument("--interval-s", type=float, default=5.0)
    parser.add_argument("--depth", type=int, default=12)
    parser.add_argument("--skip-range-cap", action="store_true")
    parser.add_argument("--skip-head-stability", action="store_true")
    parser.add_argument(
        "--include-execution-trace",
        action="store_true",
        help="attempt debug_traceTransaction on recorded lifecycle transactions",
    )
    parser.add_argument(
        "--transactions",
        default=None,
        help="transaction evidence JSON; defaults to recorded Bohr 968 lifecycle",
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    if args.max_range < 1 or args.max_results < 1:
        parser.error("--max-range and --max-results must be positive")
    if args.samples < 1 or args.interval_s < 0 or args.depth < 0:
        parser.error("--samples must be positive; --interval-s/--depth cannot be negative")

    try:
        metadata, plan = build_plan(args)
    except ValueError as exc:
        parser.error(str(exc))

    out_dir = pathlib.Path(args.out_dir)
    if not out_dir.is_absolute():
        out_dir = ROOT / out_dir

    if not args.dry_run:
        out_dir.mkdir(parents=True, exist_ok=True)

    results = []
    produced = []
    for name, command, output in plan:
        step = run_step(name, command, args.dry_run)
        results.append(step)
        if not args.dry_run and output.exists():
            produced.append(
                {
                    "path": str(output.relative_to(ROOT)),
                    "sha256": sha256_file(output),
                    "bytes": output.stat().st_size,
                }
            )

    manifest = {
        **metadata,
        "dry_run": args.dry_run,
        "steps": results,
        "artifacts": produced,
        "completed_at": iso_now(),
    }

    if args.dry_run:
        print(json.dumps(manifest, indent=2))
        return 0

    manifest_path = out_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, indent=2))

    failed = [step for step in results if step["status"] == "failed"]
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
