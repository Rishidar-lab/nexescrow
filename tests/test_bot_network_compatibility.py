"""Offline tests for the BOT network-compatibility harness.

No network, RPC, transaction, or deployment is performed here.
"""

from __future__ import annotations

import argparse
import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


def load_script(name: str, path: pathlib.Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


harness = load_script(
    "bot_network_compatibility",
    ROOT / "scripts" / "run-bot-network-compatibility.py",
)
observer = load_script(
    "bot_head_stability",
    ROOT / "scripts" / "observe-bot-head-stability.py",
)
trace_probe = load_script(
    "bot_cancun_execution",
    ROOT / "scripts" / "probe-cancun-execution.py",
)


class TestRpcUrlSafety(unittest.TestCase):
    def test_accepts_public_https_rpc(self) -> None:
        self.assertEqual(
            harness.validate_public_rpc_url("https://rpc.bohr.life"),
            "https://rpc.bohr.life",
        )

    def test_rejects_rpc_url_with_query_secret(self) -> None:
        with self.assertRaises(ValueError):
            harness.validate_public_rpc_url("https://rpc.example/?key=secret")

    def test_rejects_rpc_url_with_userinfo(self) -> None:
        with self.assertRaises(ValueError):
            harness.validate_public_rpc_url("https://user:secret@rpc.example")


class TestHarnessGates(unittest.TestCase):
    def make_args(self, **overrides):
        values = {
            "chain_id": 968,
            "rpc_url": None,
            "out_dir": "docs/evidence/bot-network-compatibility",
            "max_range": 2000,
            "max_results": 10000,
            "spans": "500,1000,2000",
            "samples": 2,
            "interval_s": 0.0,
            "depth": 12,
            "skip_range_cap": False,
            "skip_head_stability": False,
            "include_execution_trace": False,
            "transactions": None,
            "dry_run": True,
        }
        values.update(overrides)
        return argparse.Namespace(**values)

    def test_968_plan_is_read_only_and_uses_recorded_deployment(self) -> None:
        metadata, steps = harness.build_plan(self.make_args())
        self.assertEqual(metadata["chain_id"], 968)
        self.assertTrue(metadata["read_only"])
        commands = [item for _, command, _ in steps for item in command]
        self.assertIn("0x6448668ae9cbbc41617c2bd5e4f29279320a2700", commands)
        self.assertIn("26178651", commands)
        self.assertIn(
            "0x4216d1e1eb33e296e3a3040baa723b507ce2da449d60e6ffe9456cecacf6da61",
            commands,
        )
        self.assertEqual(
            [name for name, _, _ in steps],
            ["rpc-capability", "eth-getLogs-range-cap", "head-stability"],
        )

    def test_only_968_is_accepted(self) -> None:
        with self.assertRaises(ValueError):
            harness.build_plan(self.make_args(chain_id=677))

    def test_skip_flags_remove_optional_steps(self) -> None:
        _, steps = harness.build_plan(
            self.make_args(skip_range_cap=True, skip_head_stability=True)
        )
        names = [name for name, _, _ in steps]
        self.assertNotIn("eth-getLogs-range-cap", names)
        self.assertNotIn("head-stability", names)
        self.assertIn("rpc-capability", names)

    def test_range_cap_rejects_values_above_limit(self) -> None:
        with self.assertRaisesRegex(ValueError, "2000-block limit"):
            harness.build_plan(self.make_args(max_range=2001))

    def test_span_validation_errors(self) -> None:
        for raw in ("", "500,,1000", "abc", "0", "2500"):
            with self.subTest(raw=raw):
                with self.assertRaises(ValueError):
                    harness.parse_span_list(raw)

    def test_parse_span_list_accepts_ordered_values(self) -> None:
        self.assertEqual(harness.parse_span_list("500, 1000,2000"), [500, 1000, 2000])

    def test_execution_trace_step_is_added_on_968(self) -> None:
        _, steps = harness.build_plan(self.make_args(include_execution_trace=True))
        names = [name for name, _, _ in steps]
        self.assertIn("execution-trace-inventory", names)


class TestExecutionTraceAnalysis(unittest.TestCase):
    def test_cancun_opcode_and_precompile_call_are_reported(self) -> None:
        logs = [
            {"op": "TLOAD", "stack": []},
            {"op": "STATICCALL", "stack": ["00", "00", "00", "00", "02", "ffff"]},
        ]
        analysis = trace_probe.analyze_struct_logs(logs)
        self.assertEqual(analysis["cancun_specific_executed"], ["TLOAD"])
        self.assertEqual(
            analysis["standard_precompile_calls_observed"][0]["name"],
            "sha256",
        )

    def test_non_precompile_call_is_not_mislabeled(self) -> None:
        logs = [
            {"op": "CALL", "stack": ["00", "00", "00", "00", "00", "1234", "ffff"]}
        ]
        analysis = trace_probe.analyze_struct_logs(logs)
        self.assertEqual(analysis["standard_precompile_calls_observed"], [])


class TestHeadStabilityAnalysis(unittest.TestCase):
    def test_parent_link_break_is_detected(self) -> None:
        blocks = [
            {"number": 10, "hash": "0xaaa", "parentHash": "0x999"},
            {"number": 11, "hash": "0xbbb", "parentHash": "0xwrong"},
        ]
        breaks = observer.analyze_snapshot(blocks)
        self.assertEqual(len(breaks), 1)
        self.assertEqual(breaks[0]["height"], 11)

    def test_valid_parent_link_is_not_flagged(self) -> None:
        blocks = [
            {"number": 10, "hash": "0xaaa", "parentHash": "0x999"},
            {"number": 11, "hash": "0xbbb", "parentHash": "0xaaa"},
        ]
        self.assertEqual(observer.analyze_snapshot(blocks), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
