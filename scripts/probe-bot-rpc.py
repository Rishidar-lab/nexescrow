#!/usr/bin/env python3
"""
Conservative, sequential BOT Chain JSON-RPC capability probe.

Read-only: it never sends transactions or raw transactions. It issues one request
at a time with a pause between calls, retries transient gateway failures with
backoff, repeats each measurement a small number of times, and stops range growth
on failure or unreasonable latency.

Usage:
  python3 scripts/probe-bot-rpc.py \
    --name bot-bohr-testnet \
    --rpc-url https://rpc.bohr.life \
    --expected-chain-id 968 \
    --log-address 0x75edC9335175Fc0552D51D48439F229c10420fe3 \
    --historical-block 26170440 \
    --receipt-tx 0xbfe1c6eedd53e4ee240bb60ca9bfccebe6b8e0953ba8630b8ddd97706c0a963c \
    --out docs/evidence/bot-rpc-capability-bohr.json

Measured methods: eth_chainId, eth_blockNumber, eth_getBlockByNumber, eth_getCode,
eth_call, eth_estimateGas, eth_getTransactionReceipt, eth_getLogs (single latest,
single historical, then progressively larger ranges until failure or slow).

Transient HTTP 429/502/503/504 and network errors are retried with backoff and
every physical attempt is recorded, so gateway flakiness is evidence rather than
noise.
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"
ZERO_HASH = "0x" + "00" * 32
RETRYABLE_HTTP = {429, 502, 503, 504}
MAX_ATTEMPTS = 5
BACKOFF_S = [3, 6, 12, 24]
LATENCY_SANITY_MS = 10_000
MAX_RANGE = 50_000
REQUEST_TIMEOUT_S = 25.0
PAUSE_BETWEEN_REQUESTS_S = 1.0
REPEATS = 3


def iso_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def to_int(value, default=None):
    try:
        if isinstance(value, str) and value.startswith("0x"):
            return int(value, 16)
        if value is None:
            return default
        return int(value)
    except (TypeError, ValueError):
        return default


class Rpc:
    def __init__(self, url: str):
        self.url = url
        self.request_count = 0

    def call_once(self, method: str, params: list) -> dict:
        payload = json.dumps(
            {"jsonrpc": "2.0", "id": 1, "method": method, "params": params}
        ).encode()
        request = urllib.request.Request(
            self.url,
            data=payload,
            headers={"Content-Type": "application/json", "User-Agent": "nexescrow-rpc-probe/1.0"},
            method="POST",
        )
        started = time.monotonic()
        self.request_count += 1
        http_status = None
        headers: dict[str, str] = {}
        error_code = None
        error_message = None
        result = None
        outcome = "ok"
        raw_body = None

        try:
            with urllib.request.urlopen(request, timeout=REQUEST_TIMEOUT_S) as response:
                http_status = response.status
                headers = {k.lower(): v for k, v in response.headers.items()}
                raw_body = response.read().decode("utf-8", errors="replace")
        except urllib.error.HTTPError as exc:
            http_status = exc.code
            headers = {k.lower(): v for k, v in (exc.headers.items() if exc.headers else [])}
            try:
                raw_body = exc.read().decode("utf-8", errors="replace")
            except Exception:
                raw_body = None
        except TimeoutError:
            outcome = "timeout"
        except urllib.error.URLError as exc:
            if isinstance(exc.reason, TimeoutError):
                outcome = "timeout"
            else:
                outcome = "network_error"
                error_message = str(exc.reason)
        except Exception as exc:  # noqa: BLE001 - a probe records, never crashes
            outcome = "network_error"
            error_message = str(exc)

        elapsed_ms = round((time.monotonic() - started) * 1000, 1)

        if outcome == "ok" and raw_body is not None:
            try:
                parsed = json.loads(raw_body)
                if parsed.get("error"):
                    error_code = parsed["error"].get("code")
                    error_message = parsed["error"].get("message")
                    outcome = "rpc_error"
                else:
                    result = parsed.get("result")
            except json.JSONDecodeError:
                outcome = "invalid_json"
                error_message = (raw_body or "")[:200]

        return {
            "method": method,
            "outcome": outcome,
            "http_status": http_status,
            "error_code": error_code,
            "error_message": error_message,
            "latency_ms": elapsed_ms,
            "result": result,
            "response_headers": {
                k: headers[k]
                for k in headers
                if k in ("retry-after", "server", "date", "content-type")
                or k.startswith("x-ratelimit")
            },
            "raw_body_excerpt": (raw_body or "")[:300]
            if outcome in ("rpc_error", "invalid_json")
            else None,
        }

    def call_with_retry(self, method: str, params: list) -> dict:
        attempts = []
        for attempt in range(MAX_ATTEMPTS):
            record = self.call_once(method, params)
            attempts.append(
                {
                    "attempt": attempt + 1,
                    "outcome": record["outcome"],
                    "http_status": record["http_status"],
                    "error_code": record["error_code"],
                    "latency_ms": record["latency_ms"],
                }
            )
            retryable = (
                record["http_status"] in RETRYABLE_HTTP
                or record["outcome"] in ("timeout", "network_error")
            )
            if record["outcome"] == "ok" or not retryable:
                break
            if attempt < MAX_ATTEMPTS - 1:
                time.sleep(BACKOFF_S[min(attempt, len(BACKOFF_S) - 1)])
        record["attempts"] = attempts
        record["physical_requests"] = len(attempts)
        return record

    def measure(self, test_id: str, method: str, params: list, result_counter=None) -> dict:
        measurements = []
        for _ in range(REPEATS):
            measurements.append(self.call_with_retry(method, params))
            time.sleep(PAUSE_BETWEEN_REQUESTS_S)

        latencies = [m["latency_ms"] for m in measurements]
        outcomes = [m["outcome"] for m in measurements]
        successes = [m for m in measurements if m["outcome"] == "ok"]
        result_count = None
        first_result = None
        if successes:
            first_result = successes[0]["result"]
            if result_counter is not None:
                result_count = result_counter(first_result)

        retries_used = sum(max(0, m["physical_requests"] - 1) for m in measurements)
        http_503 = sum(
            1
            for m in measurements
            for a in m["attempts"]
            if a["http_status"] == 503
        )

        return {
            "id": test_id,
            "method": method,
            "params": params,
            "repeats": REPEATS,
            "outcomes": outcomes,
            "all_ok": all(o == "ok" for o in outcomes),
            "stable": len(set(outcomes)) == 1,
            "retries_used": retries_used,
            "http_503_attempts": http_503,
            "physical_requests": sum(m["physical_requests"] for m in measurements),
            "latency_ms": {
                "samples": latencies,
                "min": min(latencies),
                "median": round(statistics.median(latencies), 1),
                "max": max(latencies),
            },
            "http_status": next((m["http_status"] for m in measurements if m["http_status"]), None),
            "error_code": next((m["error_code"] for m in measurements if m["error_code"] is not None), None),
            "error_message": next((m["error_message"] for m in measurements if m["error_message"]), None),
            "result_count": result_count,
            "result_excerpt": _excerpt(first_result),
            "response_headers": next(
                (m["response_headers"] for m in measurements if m["response_headers"]), {}
            ),
            "attempts": [a for m in measurements for a in m["attempts"]],
        }


def _excerpt(result):
    text = json.dumps(result) if result is not None else None
    if text is None:
        return None
    return text if len(text) <= 200 else text[:200] + "...(truncated)"


def count_logs(result):
    return len(result) if isinstance(result, list) else None


def count_block_txs(result):
    return len(result.get("transactions", [])) if isinstance(result, dict) else None


def count_hex_bytes(result):
    if isinstance(result, str) and result.startswith("0x"):
        return (len(result) - 2) // 2
    return None


def probe_network(args) -> dict:
    rpc = Rpc(args.rpc_url)
    report = {
        "name": args.name,
        "rpc_url": args.rpc_url,
        "expected_chain_id": args.expected_chain_id,
        "generated_at": iso_now(),
        "read_only": True,
        "request_parameters": {
            "repeats": REPEATS,
            "timeout_s": REQUEST_TIMEOUT_S,
            "pause_between_requests_s": PAUSE_BETWEEN_REQUESTS_S,
            "retry_backoff_s": BACKOFF_S,
            "max_attempts_per_request": MAX_ATTEMPTS,
            "latency_sanity_ms": LATENCY_SANITY_MS,
            "max_range_attempted": args.max_range,
            "max_results_before_stop": args.max_results,
        },
        "tests": [],
        "get_logs_ranges": [],
        "rate_limit_observations": [],
        "gateway_notes": (
            "HTTP 503 (nginx 'Service Temporarily Unavailable') is retried with backoff; "
            "every physical attempt is recorded."
        ),
    }

    # eth_chainId
    chain_id_test = rpc.measure("eth_chainId", "eth_chainId", [])
    chain_record = rpc.call_with_retry("eth_chainId", [])
    chain_id = to_int(chain_record.get("result"))
    report["tests"].append(chain_id_test)
    report["observed_chain_id"] = chain_id
    report["chain_id_matches_expected"] = (
        chain_id == args.expected_chain_id if args.expected_chain_id is not None else None
    )
    time.sleep(PAUSE_BETWEEN_REQUESTS_S)

    # eth_blockNumber
    block_test = rpc.measure("eth_blockNumber", "eth_blockNumber", [])
    block_record = rpc.call_with_retry("eth_blockNumber", [])
    latest_block = to_int(block_record.get("result"))
    report["tests"].append(block_test)
    report["latest_block"] = latest_block
    time.sleep(PAUSE_BETWEEN_REQUESTS_S)

    if latest_block is None:
        report["fatal"] = "eth_blockNumber did not return a block number"
        report["total_requests_issued"] = rpc.request_count
        return report

    # eth_getBlockByNumber: latest + historical
    report["tests"].append(
        rpc.measure(
            "eth_getBlockByNumber(latest,false)",
            "eth_getBlockByNumber",
            [hex(latest_block), False],
            result_counter=count_block_txs,
        )
    )
    historical_height = args.historical_block or max(1, latest_block - min(latest_block - 1, 100_000))
    report["tests"].append(
        rpc.measure(
            f"eth_getBlockByNumber({hex(historical_height)},false)",
            "eth_getBlockByNumber",
            [hex(historical_height), False],
            result_counter=count_block_txs,
        )
    )
    report["historical_block_probed"] = historical_height

    # Receipt target: explicit, else first tx of the latest block.
    tx_hash = args.receipt_tx
    if not tx_hash:
        block_full = rpc.call_with_retry("eth_getBlockByNumber", [hex(latest_block), False])
        time.sleep(PAUSE_BETWEEN_REQUESTS_S)
        if block_full["outcome"] == "ok" and isinstance(block_full["result"], dict):
            txs = block_full["result"].get("transactions") or []
            if txs and isinstance(txs[0], str):
                tx_hash = txs[0]
    report["receipt_target"] = tx_hash or ZERO_HASH
    report["receipt_target_source"] = (
        "operator-provided" if args.receipt_tx else ("latest block tx" if tx_hash else "zero hash")
    )

    # Log address: explicit, else adaptive discovery over sampled single blocks.
    log_address = args.log_address
    discovery = []
    if log_address:
        report["log_filter"] = {
            "address": log_address,
            "source": "operator-provided",
            "note": "address filter pinned from prior explorer/RPC evidence",
        }
    else:
        candidates = _candidate_heights(latest_block)
        for height in candidates:
            record = rpc.call_with_retry("eth_getLogs", [{"fromBlock": hex(height), "toBlock": hex(height)}])
            time.sleep(PAUSE_BETWEEN_REQUESTS_S)
            discovery.append({"block": height, "outcome": record["outcome"], "count": count_logs(record["result"])})
            if record["outcome"] == "ok" and isinstance(record["result"], list) and record["result"]:
                first = record["result"][0]
                if isinstance(first, dict) and isinstance(first.get("address"), str):
                    log_address = first["address"]
                    break
        report["log_filter"] = {
            "address": log_address,
            "source": "adaptive discovery",
            "discovery": discovery,
            "note": (
                "address filter discovered from real logs"
                if log_address
                else "no log-emitting address found; ranges probed with zero-address filter"
            ),
        }

    # eth_getCode
    code_address = log_address or ZERO_ADDRESS
    report["tests"].append(
        rpc.measure(
            f"eth_getCode({code_address})",
            "eth_getCode",
            [code_address, "latest"],
            result_counter=count_hex_bytes,
        )
    )

    # eth_call: one guaranteed-success EOA call plus one real contract call
    # (totalSupply() = 0x18160ddd) when a contract address is available.
    report["tests"].append(
        rpc.measure(
            f"eth_call(empty data -> {ZERO_ADDRESS})",
            "eth_call",
            [{"to": ZERO_ADDRESS, "data": "0x"}, "latest"],
            result_counter=count_hex_bytes,
        )
    )
    if log_address:
        report["tests"].append(
            rpc.measure(
                f"eth_call(totalSupply() -> {log_address})",
                "eth_call",
                [{"to": log_address, "data": "0x18160ddd"}, "latest"],
                result_counter=count_hex_bytes,
            )
        )

    # eth_estimateGas (0-value transfer to self)
    report["tests"].append(
        rpc.measure(
            "eth_estimateGas(0-value transfer)",
            "eth_estimateGas",
            [
                {
                    "from": "0x0000000000000000000000000000000000000001",
                    "to": "0x0000000000000000000000000000000000000001",
                    "value": "0x0",
                }
            ],
            result_counter=to_int,
        )
    )

    # eth_getTransactionReceipt
    report["tests"].append(
        rpc.measure(
            f"eth_getTransactionReceipt({report['receipt_target'][:12]}...)",
            "eth_getTransactionReceipt",
            [report["receipt_target"]],
        )
    )

    # eth_getLogs: single latest, single historical, then progressive ranges.
    range_targets = [
        ("single latest block", latest_block, latest_block),
        ("single historical block", historical_height, historical_height),
        ("10-block range", max(1, latest_block - 10), latest_block),
        ("100-block range", max(1, latest_block - 100), latest_block),
        ("1000-block range", max(1, latest_block - 1000), latest_block),
    ]
    span = 2_000
    while span <= args.max_range:
        range_targets.append((f"{span}-block range", max(1, latest_block - span + 1), latest_block))
        span *= 2

    for label, from_block, to_block in range_targets:
        params = [{"fromBlock": hex(from_block), "toBlock": hex(to_block)}]
        if log_address:
            params[0]["address"] = log_address
        test = rpc.measure(f"eth_getLogs:{label}", "eth_getLogs", params, result_counter=count_logs)
        test["range"] = {
            "label": label,
            "from_block": from_block,
            "to_block": to_block,
            "block_span": to_block - from_block + 1,
            "address_filter": log_address,
        }
        report["get_logs_ranges"].append(test)

        if not test["all_ok"]:
            report["range_stop_reason"] = f"stopped at {label}: not all repeats succeeded"
            break
        if test["latency_ms"]["median"] > LATENCY_SANITY_MS:
            report["range_stop_reason"] = f"stopped after {label}: median latency exceeded {LATENCY_SANITY_MS}ms"
            break
        if test["result_count"] is not None and test["result_count"] > args.max_results:
            report["range_stop_reason"] = (
                f"stopped after {label}: result volume {test['result_count']} exceeded "
                f"practical payload limit {args.max_results}"
            )
            break

    # Rate-limit observation: a short, strictly sequential burst of light calls.
    for _ in range(5):
        record = rpc.call_once("eth_blockNumber", [])
        report["rate_limit_observations"].append(
            {
                "outcome": record["outcome"],
                "http_status": record["http_status"],
                "latency_ms": record["latency_ms"],
                "headers": record["response_headers"],
            }
        )
    report["total_requests_issued"] = rpc.request_count
    report["generated_at_end"] = iso_now()
    return report


def _candidate_heights(latest: int) -> list[int]:
    candidates = []
    for delta in (0, 1, 10, 100, 1_000, 10_000, 100_000):
        height = latest - delta
        if height > 0:
            candidates.append(height)
    for fraction in (0.5, 0.25, 0.1, 0.01):
        height = int(latest * fraction)
        if height > 0 and height not in candidates:
            candidates.append(height)
    return candidates[:8]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True)
    parser.add_argument("--rpc-url", required=True)
    parser.add_argument("--expected-chain-id", type=int, default=None)
    parser.add_argument("--log-address", default=None)
    parser.add_argument("--historical-block", type=int, default=None)
    parser.add_argument("--receipt-tx", default=None)
    parser.add_argument("--max-range", type=int, default=MAX_RANGE)
    parser.add_argument("--max-results", type=int, default=10_000)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    report = probe_network(args)

    with open(args.out, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2)
        handle.write("\n")

    summary = {
        "network": report["name"],
        "observed_chain_id": report.get("observed_chain_id"),
        "latest_block": report.get("latest_block"),
        "methods_tested": len(report.get("tests", [])),
        "get_logs_ranges": [
            {
                "label": t["range"]["label"],
                "span": t["range"]["block_span"],
                "all_ok": t["all_ok"],
                "median_ms": t["latency_ms"]["median"],
                "count": t["result_count"],
                "http_503_attempts": t["http_503_attempts"],
                "error_code": t["error_code"],
            }
            for t in report.get("get_logs_ranges", [])
        ],
        "range_stop_reason": report.get("range_stop_reason"),
        "total_requests": report.get("total_requests_issued"),
    }
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
