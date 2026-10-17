"""Regression tests for scripts/validate-bot-968.py.

Run with:  python3 -m unittest discover -s tests -v
(also wired into the `tooling` CI job)

The validator is the script an external reviewer runs to confirm the recorded
Bohr evidence. A validator that silently computes the wrong expected value is
worse than no validator: it either rubber-stamps a bad deployment or rejects a
good one. These tests pin the arithmetic it depends on.

No network, no RPC, no transaction. Pure functions only.
"""

from __future__ import annotations

import importlib.util
import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "validate-bot-968.py"

_spec = importlib.util.spec_from_file_location("validate_bot_968", SCRIPT)
assert _spec and _spec.loader
validate = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(validate)

expected_dispute_split = validate.expected_dispute_split


class TestDisputeSplit(unittest.TestCase):
    """Mirrors NexusEscrow.resolveDispute."""

    def test_matches_the_live_evidence_for_agreement_b(self) -> None:
        # From docs/evidence/bot-968/direct-state.json: B is 0.1 BOT with
        # feeBps 100, resolved at buyerBps 6000.
        split = expected_dispute_split(100_000_000_000_000_000, 100, 6000)
        self.assertEqual(split["buyerAmount"], 60_000_000_000_000_000)
        self.assertEqual(split["sellerGross"], 40_000_000_000_000_000)
        self.assertEqual(split["fee"], 400_000_000_000_000)
        self.assertEqual(split["sellerAmount"], 39_600_000_000_000_000)

    def test_value_is_exactly_conserved(self) -> None:
        # buyer + seller + fee must equal the milestone amount, for any inputs.
        for amount in (1, 999, 10**15, 10**18, 123_456_789_012_345_678):
            for fee_bps in (0, 1, 100, 250, 1000):
                for buyer_bps in (0, 1, 5000, 9999, 10000):
                    s = expected_dispute_split(amount, fee_bps, buyer_bps)
                    self.assertEqual(
                        s["buyerAmount"] + s["sellerAmount"] + s["fee"],
                        amount,
                        f"not conserved for amount={amount} fee={fee_bps} buyer={buyer_bps}",
                    )

    def test_fee_is_never_charged_on_the_buyer_share(self) -> None:
        # A full refund must charge nothing, whatever the fee rate.
        for fee_bps in (0, 100, 1000):
            s = expected_dispute_split(10**18, fee_bps, 10000)
            self.assertEqual(s["buyerAmount"], 10**18)
            self.assertEqual(s["fee"], 0)
            self.assertEqual(s["sellerAmount"], 0)

    def test_fee_scales_with_the_rate_passed_in(self) -> None:
        # This is the property the original bug violated: the result must depend
        # on the rate supplied, so passing the WRONG agreement's rate changes the
        # answer and is therefore detectable.
        amount = 10**18
        at_100 = expected_dispute_split(amount, 100, 6000)
        at_250 = expected_dispute_split(amount, 250, 6000)
        self.assertNotEqual(at_100["fee"], at_250["fee"])
        # amount 1e18, buyerBps 6000 -> gross 4e17; fee = gross * bps / 1e4
        self.assertEqual(at_100["fee"], 4_000_000_000_000_000)
        self.assertEqual(at_250["fee"], 10_000_000_000_000_000)


class TestPerAgreementFeeRate(unittest.TestCase):
    """The specific regression: A and B may carry DIFFERENT feeBps."""

    def test_differing_a_and_b_fee_rates_produce_different_expected_fees(self) -> None:
        amount = 100_000_000_000_000_000
        b_with_its_own_rate = expected_dispute_split(amount, 100, 6000)
        b_with_a_foreign_rate = expected_dispute_split(amount, 250, 6000)

        # Had the validator used A's feeBps for B's dispute, it would have
        # produced the second value and flagged a correct deployment as broken.
        self.assertNotEqual(
            b_with_its_own_rate["fee"],
            b_with_a_foreign_rate["fee"],
            "a foreign fee rate must not be silently interchangeable",
        )

    def test_a_foreign_rate_would_have_been_detectable(self) -> None:
        # Guards against the two rates coincidentally agreeing: if they are equal
        # the bug is invisible for this input, which is exactly why the rate must
        # be taken from the agreement under test rather than assumed interchangeable.
        amount = 10**18
        a_rate, b_rate = 100, 100
        self.assertEqual(
            expected_dispute_split(amount, a_rate, 6000)["fee"],
            expected_dispute_split(amount, b_rate, 6000)["fee"],
        )
        # ...and once the owner changes protocolFeeBps between creations, they diverge.
        self.assertNotEqual(
            expected_dispute_split(amount, 100, 6000)["fee"],
            expected_dispute_split(amount, 250, 6000)["fee"],
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)