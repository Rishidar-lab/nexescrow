#!/usr/bin/env python3
"""
Read-only execution-trace probe for NexEscrow's recorded lifecycle transactions.

When the RPC supports debug_traceTransaction, this inventories opcodes actually
executed by the recorded transactions and identifies calls whose destination is
a standard precompile address (0x01..0x0a). It does not claim that an opcode or
precompile is guaranteed by BOT Chain; it only records observed trace evidence.

If the RPC does not expose debug_traceTransaction, that limitation is recorded
rather than treated as a finality/compatibility conclusion.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from urllib.parse import urlsplit

TIMEOUT_S = 30.0
RETRYABLE_HTTP = {429, 502, 503, 504}
BACKOFF_S = (1.0, 2.0)
MAX_ATTEMPTS = 3

CANCUN_SPECIFIC_OPCODES = {
    "BLOBHASH",
    "BLOBBASEFEE",
    "TLOAD",
    "TSTORE",
    "MCOPY",
}
CALL_OPCODES = {"CALL", "CALLCODE", "DELEGATECALL", "STATICCALL"}
STANDARD_PRECOMPILES = {
    0x01: "ecrecover",
    0x02: "sha256",
    0x03: "ripemd160",
    0x04: "identity",
    0x05: "modexp",
    0x06: "bn256Add",
    0x07: "bn256ScalarMul",
    0x08: "bn256Pairing",
    0x09: "blake2f",
    0x0A: "kzgPointEvaluation",
}


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


def rpc_call(url: str, method: str, params: list) -> dict:
    attempts = []
    for index in range(MAX_ATTEMPTS):
        payload = json.dumps(
            {"jsonrpc": "2.0", "id": 1, "method": method, "params": params}
        ).encode()
        req = urllib.request.Request(
            url,
            data=payload,
            headers={
                "Content-Type": "application/json",
                "User-Agent": "nexescrow-execution-trace/1.0",
            },
            method="POST",
        )
        started = time.monotonic()
        status = None
        result = None
        error = None
        outcome = "ok"
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT_S) as response:
                status = response.status
                parsed = json.loads(response.read().decode("utf-8", errors="replace"))
                if parsed.get("error"):
                    outcome = "rpc_error"
                    error = parsed["error"]
                else:
                    result = parsed.get("result")
        except urllib.error.HTTPError as exc:
            status = exc.code
            outcome = "http_error"
            error = {"message": exc.read().decode(errors="replace")[:300]}
        except TimeoutError:
            outcome = "timeout"
            error = {"message": "timeout"}
        except urllib.error.URLError as exc:
            outcome = "network_error"
            error = {"message": str(exc.reason)}
        except Exception as exc:  # noqa: BLE001
            outcome = "network_error"
            error = {"message": str(exc)}

        attempts.append(
            {
                "attempt": index + 1,
                "outcome": outcome,
                "http_status": status,
                "latency_ms": round((time.monotonic() - started) * 1000, 1),
                "error": error,
            }
        )
        retryable = status in RETRYABLE_HTTP or outcome in {"timeout", "network_error"}
        if outcome == "ok" or not retryable:
            return {
                "outcome": outcome,
                "http_status": status,
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


def hex_to_int(value) -> int | None:
    if not isinstance(value, str):
        return None
    text = value[2:] if value.startswith("0x") else value
    try:
        return int(text, 16)
    except ValueError:
        return None


def analyze_struct_logs(struct_logs: list[dict]) -> dict:
    opcodes = []
    precompile_calls = []
    for index, row in enumerate(struct_logs):
        op = str(row.get("op") or "").upper()
        if op:
            opcodes.append(op)
        if op not in CALL_OPCODES:
            continue
        stack = row.get("stack")
        if not isinstance(stack, list) or len(stack) < 2:
            continue
        target = hex_to_int(stack[-2])
        if target in STANDARD_PRECOMPILES:
            precompile_calls.append(
                {
                    "trace_index": index,
                    "opcode": op,
                    "address": f"0x{target:02x}",
                    "name": STANDARD_PRECOMPILES[target],
                }
            )

    unique = sorted(set(opcodes))
    return {
        "executed_opcode_count": len(opcodes),
        "executed_opcodes_unique": unique,
        "cancun_specific_executed": sorted(
            set(unique).intersection(CANCUN_SPECIFIC_OPCODES)
        ),
        "standard_precompile_calls_observed": precompile_calls,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rpc-url", default="https://rpc.bohr.life")
    parser.add_argument("--expected-chain-id", type=int, default=968)
    parser.add_argument(
        "--transactions",
        default="docs/evidence/bot-968/transactions.json",
        help="recorded NexEscrow lifecycle transaction JSON",
    )
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    try:
        rpc_url = validate_public_rpc_url(args.rpc_url)
    except ValueError as exc:
        parser.error(str(exc))

    tx_path = pathlib.Path(args.transactions)
    raw = json.loads(tx_path.read_text(encoding="utf-8"))
    txs = raw.get("transactions")
    if not isinstance(txs, list):
        parser.error("transactions file must contain a transactions array")

    report = {
        "schema_version": 1,
        "generated_at": iso_now(),
        "rpc_url": rpc_url,
        "expected_chain_id": args.expected_chain_id,
        "read_only": True,
        "source_transactions": str(tx_path),
        "evidence_boundary": (
            "Only successfully returned execution traces are inventoried. Observed "
            "execution does not establish BOT-wide opcode/precompile guarantees."
        ),
        "transactions": [],
    }

    chain = rpc_call(rpc_url, "eth_chainId", [])
    observed = hex_to_int(chain.get("result"))
    report["observed_chain_id"] = observed
    report["chain_id_check"] = chain
    if observed != args.expected_chain_id:
        report["fatal"] = (
            f"chain id mismatch: expected {args.expected_chain_id}, observed {observed}"
        )
        out = pathlib.Path(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        return 1

    traced = 0
    for item in txs:
        tx_hash = item.get("transactionHash")
        if not isinstance(tx_hash, str):
            continue
        trace = rpc_call(
            rpc_url,
            "debug_traceTransaction",
            [
                tx_hash,
                {
                    "disableStorage": True,
                    "disableMemory": True,
                    "disableStack": False,
                },
            ],
        )
        entry = {
            "step": item.get("step"),
            "transactionHash": tx_hash,
            "trace_outcome": trace["outcome"],
            "trace_error": trace.get("error"),
            "attempts": trace.get("attempts"),
        }
        result = trace.get("result")
        if trace["outcome"] == "ok" and isinstance(result, dict):
            struct_logs = result.get("structLogs")
            if isinstance(struct_logs, list):
                entry["analysis"] = analyze_struct_logs(struct_logs)
                traced += 1
            else:
                entry["analysis_status"] = "trace returned without structLogs"
        report["transactions"].append(entry)

    report["summary"] = {
        "transactions_supplied": len(txs),
        "transactions_traced_with_structLogs": traced,
        "trace_capability_observed": (
            "available" if traced else "not demonstrated by this run"
        ),
    }
    report["completed_at"] = iso_now()
    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report["summary"], indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
