#!/usr/bin/env python3
"""
Observe recent BOT Chain block hashes over time without sending transactions.

This can detect a hash replacement if the same height is observed with different
hashes during the sampling window. Absence of an observed replacement is not a
finality guarantee and must not be presented as one.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from urllib.parse import urlsplit

RETRYABLE_HTTP = {429, 502, 503, 504}
BACKOFF_S = (1.0, 2.0)
MAX_ATTEMPTS = 3
TIMEOUT_S = 20.0


def iso_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def validate_public_rpc_url(value: str) -> str:
    parsed = urlsplit(value)
    if parsed.scheme != "https" or not parsed.netloc:
        raise ValueError("RPC URL must be an absolute https:// URL")
    if parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ValueError(
            "RPC URL must not contain credentials, query parameters, or fragments"
        )
    return value


def _decode_hex_int(value):
    if isinstance(value, str) and value.startswith("0x"):
        try:
            return int(value, 16)
        except ValueError:
            return None
    return None


def rpc_call(url: str, method: str, params: list) -> dict:
    attempts = []
    for index in range(MAX_ATTEMPTS):
        payload = json.dumps(
            {"jsonrpc": "2.0", "id": 1, "method": method, "params": params}
        ).encode()
        request = urllib.request.Request(
            url,
            data=payload,
            headers={
                "Content-Type": "application/json",
                "User-Agent": "nexescrow-head-observer/1.0",
            },
            method="POST",
        )
        started = time.monotonic()
        http_status = None
        outcome = "ok"
        error = None
        result = None
        try:
            with urllib.request.urlopen(request, timeout=TIMEOUT_S) as response:
                http_status = response.status
                parsed = json.loads(response.read().decode("utf-8", errors="replace"))
                if parsed.get("error"):
                    outcome = "rpc_error"
                    error = parsed["error"]
                else:
                    result = parsed.get("result")
        except urllib.error.HTTPError as exc:
            http_status = exc.code
            outcome = "http_error"
            error = {"message": exc.read().decode(errors="replace")[:300]}
        except TimeoutError:
            outcome = "timeout"
            error = {"message": "timeout"}
        except urllib.error.URLError as exc:
            outcome = "network_error"
            error = {"message": str(exc.reason)}
        except Exception as exc:  # noqa: BLE001 - evidence probe records failure
            outcome = "network_error"
            error = {"message": str(exc)}

        record = {
            "attempt": index + 1,
            "outcome": outcome,
            "http_status": http_status,
            "latency_ms": round((time.monotonic() - started) * 1000, 1),
            "error": error,
        }
        attempts.append(record)

        retryable = http_status in RETRYABLE_HTTP or outcome in {
            "timeout",
            "network_error",
        }
        if outcome == "ok" or not retryable:
            return {
                "outcome": outcome,
                "http_status": http_status,
                "result": result,
                "error": error,
                "attempts": attempts,
            }
        if index < MAX_ATTEMPTS - 1:
            time.sleep(BACKOFF_S[min(index, len(BACKOFF_S) - 1)])

    return {
        "outcome": attempts[-1]["outcome"],
        "http_status": attempts[-1]["http_status"],
        "result": None,
        "error": attempts[-1]["error"],
        "attempts": attempts,
    }


def analyze_snapshot(blocks: list[dict]) -> list[dict]:
    breaks = []
    ordered = sorted(blocks, key=lambda row: row["number"])
    for previous, current in zip(ordered, ordered[1:]):
        if current["number"] != previous["number"] + 1:
            continue
        if current.get("parentHash") != previous.get("hash"):
            breaks.append(
                {
                    "previous_height": previous["number"],
                    "previous_hash": previous.get("hash"),
                    "height": current["number"],
                    "parent_hash": current.get("parentHash"),
                }
            )
    return breaks


def observe(
    rpc_url: str,
    expected_chain_id: int,
    samples: int,
    interval_s: float,
    depth: int,
    name: str,
) -> tuple[dict, int]:
    report = {
        "schema_version": 1,
        "name": name,
        "rpc_url": rpc_url,
        "expected_chain_id": expected_chain_id,
        "generated_at": iso_now(),
        "read_only": True,
        "evidence_boundary": (
            "Observed block hashes are empirical samples only. No observed hash "
            "replacement does not establish a finality or reorganisation guarantee."
        ),
        "parameters": {
            "samples": samples,
            "interval_s": interval_s,
            "depth": depth,
            "max_attempts": MAX_ATTEMPTS,
            "timeout_s": TIMEOUT_S,
        },
        "samples": [],
        "hash_changes": [],
        "parent_link_breaks": [],
    }

    chain = rpc_call(rpc_url, "eth_chainId", [])
    observed_chain_id = _decode_hex_int(chain.get("result"))
    report["observed_chain_id"] = observed_chain_id
    report["chain_id_check"] = chain
    if observed_chain_id != expected_chain_id:
        report["fatal"] = (
            f"chain id mismatch: expected {expected_chain_id}, observed {observed_chain_id}"
        )
        report["completed_at"] = iso_now()
        return report, 1

    seen: dict[int, str] = {}

    for sample_index in range(samples):
        head_result = rpc_call(rpc_url, "eth_blockNumber", [])
        head = _decode_hex_int(head_result.get("result"))
        sample = {
            "index": sample_index,
            "observed_at": iso_now(),
            "head_call": head_result,
            "head": head,
            "blocks": [],
        }
        if head is None:
            sample["error"] = "eth_blockNumber did not return a valid height"
            report["samples"].append(sample)
        else:
            start = max(0, head - depth)
            for height in range(start, head + 1):
                record = rpc_call(rpc_url, "eth_getBlockByNumber", [hex(height), False])
                block = record.get("result")
                if record["outcome"] != "ok" or not isinstance(block, dict):
                    sample["blocks"].append(
                        {
                            "number": height,
                            "outcome": record["outcome"],
                            "error": record.get("error"),
                        }
                    )
                    continue

                row = {
                    "number": height,
                    "hash": block.get("hash"),
                    "parentHash": block.get("parentHash"),
                    "timestamp": block.get("timestamp"),
                    "outcome": "ok",
                }
                sample["blocks"].append(row)
                block_hash = row.get("hash")
                if isinstance(block_hash, str):
                    old = seen.get(height)
                    if old is not None and old != block_hash:
                        report["hash_changes"].append(
                            {
                                "height": height,
                                "previous_hash": old,
                                "replacement_hash": block_hash,
                                "sample_index": sample_index,
                                "observed_at": sample["observed_at"],
                            }
                        )
                    seen[height] = block_hash

            valid_blocks = [
                row for row in sample["blocks"] if row.get("outcome") == "ok"
            ]
            for item in analyze_snapshot(valid_blocks):
                report["parent_link_breaks"].append(
                    {**item, "sample_index": sample_index}
                )
            report["samples"].append(sample)

        if sample_index < samples - 1:
            time.sleep(interval_s)

    report["summary"] = {
        "samples_completed": len(report["samples"]),
        "unique_heights_seen": len(seen),
        "hash_replacements_observed": len(report["hash_changes"]),
        "parent_link_breaks_observed": len(report["parent_link_breaks"]),
    }
    report["completed_at"] = iso_now()
    return report, 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True)
    parser.add_argument("--rpc-url", required=True)
    parser.add_argument("--expected-chain-id", type=int, required=True)
    parser.add_argument("--samples", type=int, default=6)
    parser.add_argument("--interval-s", type=float, default=5.0)
    parser.add_argument("--depth", type=int, default=12)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    if args.samples < 1:
        parser.error("--samples must be positive")
    if args.interval_s < 0 or args.depth < 0:
        parser.error("--interval-s and --depth cannot be negative")

    try:
        rpc_url = validate_public_rpc_url(args.rpc_url)
    except ValueError as exc:
        parser.error(str(exc))

    report, exit_code = observe(
        rpc_url=rpc_url,
        expected_chain_id=args.expected_chain_id,
        samples=args.samples,
        interval_s=args.interval_s,
        depth=args.depth,
        name=args.name,
    )

    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report["summary"] if "summary" in report else report, indent=2))
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
