#!/usr/bin/env python3
"""
Supplementary BOT Chain eth_getLogs hard-range-cap probe.

Uses an empty-result filter (zero address) so payload volume does not confound the
question: does the RPC gateway impose a maximum block range? One sequential
request per span, with retries on transient 5xx, then stops at the first failure.

Read-only; no transactions. Usage:

  python3 scripts/probe-bot-rpc-range-cap.py \
    --name bot-bohr-testnet --rpc-url https://rpc.bohr.life \
    --spans 8000000,16000000,32000000 \
    --out /tmp/bot-bohr-range-cap.json
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone

RETRYABLE_HTTP = {429, 502, 503, 504}
MAX_ATTEMPTS = 4
BACKOFF_S = [3, 6, 12]
TIMEOUT_S = 40.0
PAUSE_S = 2.0
ZERO_ADDRESS = "0x0000000000000000000000000000000000000000"


def iso_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def rpc_call(url: str, method: str, params: list) -> dict:
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": method, "params": params}).encode()
    request = urllib.request.Request(
        url,
        data=body,
        headers={"Content-Type": "application/json", "User-Agent": "nexescrow-range-probe/1.0"},
        method="POST",
    )
    started = time.monotonic()
    outcome, http_status, error_code, error_message, result = "ok", None, None, None, None
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT_S) as response:
            http_status = response.status
            parsed = json.loads(response.read().decode())
            if parsed.get("error"):
                outcome, error_code, error_message = (
                    "rpc_error",
                    parsed["error"].get("code"),
                    parsed["error"].get("message"),
                )
            else:
                result = parsed.get("result")
    except urllib.error.HTTPError as exc:
        http_status = exc.code
        error_message = exc.read().decode(errors="replace")[:200]
        outcome = "http_error"
    except TimeoutError:
        outcome = "timeout"
    except Exception as exc:  # noqa: BLE001
        outcome = "network_error"
        error_message = str(exc)
    return {
        "outcome": outcome,
        "http_status": http_status,
        "error_code": error_code,
        "error_message": error_message,
        "latency_ms": round((time.monotonic() - started) * 1000, 1),
        "result_count": len(result) if isinstance(result, list) else None,
        "result": result,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--name", required=True)
    parser.add_argument("--rpc-url", required=True)
    parser.add_argument("--spans", required=True, help="comma-separated block spans")
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    spans = [int(s) for s in args.spans.split(",") if s.strip()]
    report = {
        "name": args.name,
        "rpc_url": args.rpc_url,
        "generated_at": iso_now(),
        "filter": {"address": ZERO_ADDRESS, "note": "empty-result filter isolates range-cap from payload size"},
        "probes": [],
    }

    # Latest head
    head = rpc_call(args.rpc_url, "eth_blockNumber", [])
    latest = int(head["result"], 16) if head["outcome"] == "ok" and head["result"] else None
    report["latest_block"] = latest
    if latest is None:
        report["fatal"] = "eth_blockNumber failed"
        with open(args.out, "w") as fh:
            json.dump(report, fh, indent=2)
        print(json.dumps(report, indent=2))
        return 1
    time.sleep(PAUSE_S)

    for span in spans:
        from_block = max(1, latest - span + 1)
        attempt = None
        for i in range(MAX_ATTEMPTS):
            attempt = rpc_call(
                args.rpc_url,
                "eth_getLogs",
                [{"address": ZERO_ADDRESS, "fromBlock": hex(from_block), "toBlock": hex(latest)}],
            )
            retryable = attempt["http_status"] in RETRYABLE_HTTP or attempt["outcome"] in ("timeout", "network_error")
            if attempt["outcome"] == "ok" or not retryable:
                break
            if i < MAX_ATTEMPTS - 1:
                time.sleep(BACKOFF_S[min(i, len(BACKOFF_S) - 1)])
        probe = {"requested_span": span, "from_block": from_block, "to_block": latest, **attempt}
        report["probes"].append(probe)
        if probe["outcome"] != "ok":
            report["stop_reason"] = f"failed at span {span}: {probe['outcome']} {probe['error_code']}"
            break
        time.sleep(PAUSE_S)

    report["generated_at_end"] = iso_now()
    with open(args.out, "w") as fh:
        json.dump(report, fh, indent=2)
    print(json.dumps({p["requested_span"]: {k: p[k] for k in ("outcome", "http_status", "error_code", "latency_ms")} for p in report["probes"]}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
