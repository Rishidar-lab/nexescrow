"""Offline tests for the BOT RPC probe retry logic.

No network, RPC, transaction, or deployment is performed here.
"""

from __future__ import annotations

import importlib.util
import pathlib
import statistics
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[1]


def load_script(name: str, path: pathlib.Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


probe = load_script("bot_rpc_probe", ROOT / "scripts" / "probe-bot-rpc.py")


def make_record(
    method: str,
    outcome: str,
    http_status: int | None,
    latency_ms: float = 1.0,
    result=None,
) -> dict:
    return {
        "method": method,
        "outcome": outcome,
        "http_status": http_status,
        "error_code": None if outcome == "ok" else -32000,
        "error_message": None if outcome == "ok" else "rpc failure",
        "latency_ms": latency_ms,
        "result": result,
        "response_headers": {},
        "raw_body_excerpt": None,
    }


class TestCallWithRetry(unittest.TestCase):
    def setUp(self) -> None:
        self.rpc = probe.Rpc("https://rpc.bohr.life")

    def test_success_on_first_attempt_does_not_sleep(self) -> None:
        self.rpc.call_once = mock.Mock(return_value=make_record("eth_chainId", "ok", 200))
        with mock.patch("time.sleep") as sleep:
            record = self.rpc.call_with_retry("eth_chainId", [])
        self.assertEqual(self.rpc.call_once.call_count, 1)
        sleep.assert_not_called()
        self.assertEqual(record["outcome"], "ok")
        self.assertEqual(record["physical_requests"], 1)
        self.assertEqual([a["attempt"] for a in record["attempts"]], [1])

    def test_retries_503_then_succeeds(self) -> None:
        self.rpc.call_once = mock.Mock(
            side_effect=[
                make_record("eth_chainId", "rpc_error", 503),
                make_record("eth_chainId", "ok", 200),
            ]
        )
        with mock.patch("time.sleep") as sleep:
            record = self.rpc.call_with_retry("eth_chainId", [])
        self.assertEqual(self.rpc.call_once.call_count, 2)
        self.assertEqual(sleep.call_args_list, [mock.call(probe.BACKOFF_S[0])])
        self.assertEqual(record["outcome"], "ok")
        self.assertEqual(record["physical_requests"], 2)
        self.assertEqual([a["attempt"] for a in record["attempts"]], [1, 2])
        self.assertEqual(record["attempts"][0]["http_status"], 503)

    def test_non_retryable_error_breaks_immediately(self) -> None:
        self.rpc.call_once = mock.Mock(
            return_value=make_record("eth_chainId", "rpc_error", 400)
        )
        with mock.patch("time.sleep") as sleep:
            record = self.rpc.call_with_retry("eth_chainId", [])
        self.assertEqual(self.rpc.call_once.call_count, 1)
        sleep.assert_not_called()
        self.assertEqual(record["outcome"], "rpc_error")
        self.assertEqual(record["physical_requests"], 1)

    def test_timeout_exhausts_all_attempts(self) -> None:
        self.rpc.call_once = mock.Mock(
            return_value=make_record("eth_chainId", "timeout", None)
        )
        with mock.patch("time.sleep") as sleep:
            record = self.rpc.call_with_retry("eth_chainId", [])
        self.assertEqual(self.rpc.call_once.call_count, probe.MAX_ATTEMPTS)
        self.assertEqual(
            sleep.call_args_list,
            [mock.call(b) for b in probe.BACKOFF_S],
        )
        self.assertEqual(record["outcome"], "timeout")
        self.assertEqual(record["physical_requests"], probe.MAX_ATTEMPTS)
        self.assertEqual(
            [a["attempt"] for a in record["attempts"]],
            list(range(1, probe.MAX_ATTEMPTS + 1)),
        )


class TestMeasure(unittest.TestCase):
    def test_aggregates_repeated_calls(self) -> None:
        rpc = probe.Rpc("https://rpc.bohr.life")
        latencies = [10.0 * (i + 1) for i in range(probe.REPEATS)]
        records = []
        for value, latency in enumerate(latencies, start=1):
            record = make_record(
                "eth_blockNumber",
                "ok",
                200,
                latency_ms=latency,
                result={"n": value},
            )
            record["physical_requests"] = 1
            record["attempts"] = [
                {
                    "attempt": 1,
                    "outcome": "ok",
                    "http_status": 200,
                    "error_code": None,
                    "latency_ms": latency,
                }
            ]
            records.append(record)
        rpc.call_with_retry = mock.Mock(side_effect=records)
        with mock.patch("time.sleep") as sleep:
            summary = rpc.measure(
                "head-lag",
                "eth_blockNumber",
                [],
                result_counter=lambda r: r["n"],
            )
        self.assertEqual(rpc.call_with_retry.call_count, probe.REPEATS)
        self.assertEqual(
            sleep.call_args_list,
            [mock.call(probe.PAUSE_BETWEEN_REQUESTS_S)] * probe.REPEATS,
        )
        self.assertEqual(summary["outcomes"], ["ok"] * probe.REPEATS)
        self.assertTrue(summary["all_ok"])
        self.assertTrue(summary["stable"])
        self.assertEqual(summary["retries_used"], 0)
        self.assertEqual(summary["http_503_attempts"], 0)
        self.assertEqual(summary["physical_requests"], probe.REPEATS)
        self.assertEqual(summary["latency_ms"]["samples"], latencies)
        self.assertEqual(summary["latency_ms"]["min"], min(latencies))
        self.assertEqual(
            summary["latency_ms"]["median"],
            round(statistics.median(latencies), 1),
        )
        self.assertEqual(summary["latency_ms"]["max"], max(latencies))
        self.assertEqual(summary["http_status"], 200)
        self.assertEqual(summary["result_count"], 1)
        self.assertEqual(summary["result_excerpt"], '{"n": 1}')


if __name__ == "__main__":
    unittest.main()
