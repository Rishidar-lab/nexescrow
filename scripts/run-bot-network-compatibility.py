#!/usr/bin/env python3
"""
Read-only BOT Chain network-compatibility harness for NexEscrow.

This orchestrates the repository's existing RPC capability/range probes plus a
short head-stability observation. It never sends transactions. Only BOT Chain
Bohr testnet (chain 968) is supported; chain 677 is rejected outright and no
write or deployment path exists.

The resulting bundle is observational evidence only. It must not be interpreted
as a BOT Chain finality guarantee, retry policy, opcode/precompile guarantee,
security audit, or production-readiness approval.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import platform
import subprocess
import sys
from datetime import datetime, timezone
from urllib.parse import urlsplit

ROOT = pathlib.Path(__file__).resolve().parents[1]

MAX_GET_LOGS_RANGE = 2000

NETWORK_DISPLAY = {968: "BOT Chain Bohr testnet"}

CHAINS = {
    968: {
        "name": "bot-bohr-testnet",
        "rpc_url": "https://rpc.bohr.life",
        "log_address": "0x6448668ae9cbbc41617c2bd5e4f29279320a2700",
        "historical_block": 26178651,
        "receipt_tx": "0x4216d1e1eb33e296e3a3040baa723b507ce2da449d60e6ffe9456cecacf6da61",
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


def parse_span_list(raw: str) -> list[int]:
    tokens = [token.strip() for token in raw.split(",")]
    if not any(tokens):
        raise ValueError("--spans must contain at least one value")
    spans: list[int] = []
    for token in tokens:
        if not token:
            raise ValueError(
                "--spans must be a comma-separated list of positive integers"
            )
        try:
            value = int(token, 10)
        except ValueError:
            raise ValueError(f"--spans value {token!r} is not an integer") from None
        if value < 1:
            raise ValueError(f"--spans value {value} must be positive")
        if value > MAX_GET_LOGS_RANGE:
            raise ValueError(
                f"--spans value {value} exceeds the 2000-block limit"
            )
        spans.append(value)
    return spans


def git_commit() -> str | None:
    try:
        proc = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return None
    if proc.returncode != 0:
        return None
    return proc.stdout.strip() or None


def git_dirty() -> bool | None:
    try:
        proc = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return None
    if proc.returncode != 0:
        return None
    return bool(proc.stdout.strip())


def make_run_id(started_at: str, chain_id: int) -> str:
    return started_at.replace("-", "").replace(":", "") + f"-{chain_id}"


def build_run_metadata(metadata: dict, started_at: str) -> dict:
    chain_id = metadata["chain_id"]
    return {
        "schemaVersion": 1,
        "runId": make_run_id(started_at, chain_id),
        "startedAtUtc": started_at,
        "finishedAtUtc": None,
        "gitCommit": git_commit(),
        "gitDirty": git_dirty(),
        "chainId": chain_id,
        "network": NETWORK_DISPLAY.get(chain_id, metadata["network"]),
        "rpcEndpoint": metadata["rpc_url"],
        "runtime": "python",
        "runtimeVersion": platform.python_version(),
        "toolVersions": {"python": platform.python_version()},
        "harnessVersion": "1",
        "requestPolicy": {
            "maxBlockRange": MAX_GET_LOGS_RANGE,
            "maxConcurrency": 1,
            "minimumDelayMs": 1000,
        },
    }


ARTIFACT_PROJECTIONS = {
    "rpc-capability": ("tests", "test"),
    "eth_getLogs-range-cap": ("probes", "probe"),
    "head-stability": ("samples", "sample"),
}


def project_artifact(
    step_name: str, artifact_path: pathlib.Path, document: object
) -> list[dict]:
    projection = ARTIFACT_PROJECTIONS.get(step_name)
    if projection is None:
        return []
    collection_name, kind = projection
    if not isinstance(document, dict):
        return []
    records = document.get(collection_name)
    if not isinstance(records, list):
        return []
    lines: list[dict] = []
    for ordinal, record in enumerate(records):
        if not isinstance(record, dict):
            continue
        base = {
            "source": step_name,
            "artifact": artifact_path.name,
            "kind": kind,
            "ordinal": ordinal,
        }
        unit = {key: value for key, value in record.items() if key != "attempts"}
        attempts = record.get("attempts")
        if isinstance(attempts, list):
            unit["attempt_count"] = len(attempts)
        lines.append({**base, "record": unit})
        if isinstance(attempts, list):
            for attempt in attempts:
                if isinstance(attempt, dict):
                    lines.append({**base, "attempt": attempt})
    return lines


def write_json(path: pathlib.Path, payload: object) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_jsonl(path: pathlib.Path, lines: list[dict]) -> None:
    text = "".join(json.dumps(line, sort_keys=True) + "\n" for line in lines)
    path.write_text(text, encoding="utf-8")


def build_summary(
    run_metadata: dict, results: list[dict], produced: list[dict], finished_at: str
) -> dict:
    steps = [
        {
            "name": result["name"],
            "status": result["status"],
            "exitCode": result["exit_code"],
        }
        for result in results
    ]
    passed_count = sum(1 for step in steps if step["status"] == "passed")
    failed_count = sum(1 for step in steps if step["status"] == "failed")
    return {
        "schemaVersion": 1,
        "runId": run_metadata["runId"],
        "chainId": run_metadata["chainId"],
        "network": run_metadata["network"],
        "startedAtUtc": run_metadata["startedAtUtc"],
        "finishedAtUtc": finished_at,
        "steps": steps,
        "stepCount": len(steps),
        "passedCount": passed_count,
        "failedCount": failed_count,
        "artifacts": produced,
        "artifactCount": len(produced),
    }


def build_plan(args: argparse.Namespace) -> tuple[dict, list[tuple[str, list[str], pathlib.Path]]]:
    if args.chain_id not in CHAINS:
        raise ValueError(f"unsupported chain id: {args.chain_id}")
    cfg = dict(CHAINS[args.chain_id])
    if args.rpc_url:
        cfg["rpc_url"] = validate_public_rpc_url(args.rpc_url)
    else:
        cfg["rpc_url"] = validate_public_rpc_url(cfg["rpc_url"])

    if args.max_range > MAX_GET_LOGS_RANGE:
        raise ValueError(
            f"--max-range {args.max_range} exceeds the 2000-block limit"
        )
    parse_span_list(args.spans)

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
        started_at = iso_now()
        run_metadata = build_run_metadata(metadata, started_at)
        write_json(out_dir / "metadata.json", run_metadata)

    documents: dict[str, tuple[pathlib.Path, object]] = {}
    request_lines: list[dict] = []
    response_lines: list[dict] = []
    observation_lines: list[dict] = []

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
            try:
                document = json.loads(output.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                document = None
            documents[name] = (output, document)

    if not args.dry_run:
        for step_name, (artifact_path, document) in documents.items():
            for line in project_artifact(step_name, artifact_path, document):
                if "attempt" in line:
                    response_lines.append(line)
                else:
                    request_lines.append(line)
                    observation_lines.append(line)
        write_jsonl(out_dir / "requests.jsonl", request_lines)
        write_jsonl(out_dir / "responses.jsonl", response_lines)
        write_jsonl(out_dir / "observations.jsonl", observation_lines)
        finished_at = iso_now()
        run_metadata["finishedAtUtc"] = finished_at
        write_json(out_dir / "metadata.json", run_metadata)
        write_json(
            out_dir / "summary.json",
            build_summary(run_metadata, results, produced, finished_at),
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
