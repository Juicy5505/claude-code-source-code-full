"""Tests for trends — direction of travel across multiple sessions."""

import unittest

import trends

from trends import METRICS, analyze_trends, linear_slope, session_value, trend_verdict


def sess(**metric_lists):
    """Build a session (list of swing dicts) from parallel metric lists."""
    n = max(len(v) for v in metric_lists.values())
    swings = []
    for i in range(n):
        swing = {}
        for key, values in metric_lists.items():
            if i < len(values):
                swing[key] = values[i]
        swings.append(swing)
    return swings


class TestSlope(unittest.TestCase):
    def test_rising(self):
        self.assertAlmostEqual(linear_slope([1, 2, 3, 4]), 1.0, places=9)

    def test_falling(self):
        self.assertAlmostEqual(linear_slope([4, 2, 0]), -2.0, places=9)

    def test_needs_two_points(self):
        self.assertIsNone(linear_slope([5]))


class TestSessionValue(unittest.TestCase):
    def test_mean_metric(self):
        s = sess(distance_yd=[200, 210, 220])
        self.assertAlmostEqual(session_value(s, METRICS["distance_yd"]), 210.0, places=6)

    def test_cv_metric(self):
        s = sess(tempo_ratio=[3.0, 3.0, 3.0])
        # Zero spread -> cv 0.
        self.assertAlmostEqual(session_value(s, METRICS["tempo_consistency"]), 0.0, places=9)

    def test_missing_metric_is_none(self):
        s = sess(peak_g=[10, 11])
        self.assertIsNone(session_value(s, METRICS["distance_yd"]))


class TestTrendVerdict(unittest.TestCase):
    def test_distance_up_is_improving(self):
        v = trend_verdict([200, 210, 220], METRICS["distance_yd"])
        self.assertEqual(v["direction"], "rising")
        self.assertTrue(v["improving"])

    def test_heart_rate_up_is_regressing(self):
        # For HR, lower is better, so rising HR is NOT improving.
        v = trend_verdict([120, 130, 140], METRICS["hr_bpm"])
        self.assertEqual(v["direction"], "rising")
        self.assertFalse(v["improving"])

    def test_consistency_down_is_improving(self):
        # cv falling = tighter = better.
        v = trend_verdict([0.12, 0.09, 0.05], METRICS["tempo_consistency"])
        self.assertTrue(v["improving"])

    def test_tempo_toward_target_is_improving(self):
        # Moving 2.4 -> 2.7 -> 3.0 approaches the 3.0 benchmark: improving,
        # even though the raw value is rising.
        v = trend_verdict([2.4, 2.7, 3.0], METRICS["tempo_ratio"])
        self.assertTrue(v["improving"])
        self.assertEqual(v["direction"], "rising")

    def test_tempo_away_from_target_is_regressing(self):
        # 3.0 -> 3.4 -> 3.8 moves away from 3.0: regressing though still rising.
        v = trend_verdict([3.0, 3.4, 3.8], METRICS["tempo_ratio"])
        self.assertFalse(v["improving"])

    def test_single_session_undecidable(self):
        self.assertIsNone(trend_verdict([200], METRICS["distance_yd"]))

    def test_flat_metric_is_flat_not_regressing(self):
        # An unchanged metric must read flat, not regressing — the bug that a
        # zero slope on a "higher/lower is better" metric was called worse.
        for key in ("distance_yd", "hr_bpm", "tempo_consistency", "tempo_ratio"):
            v = trend_verdict([2.0, 2.0, 2.0], METRICS[key])
            self.assertEqual(v["direction"], "flat", key)
            self.assertIsNone(v["improving"], key)


class TestAnalyze(unittest.TestCase):
    def test_multi_metric_multi_session(self):
        sessions = [
            sess(distance_yd=[200, 205], tempo_ratio=[2.6, 2.7], hr_bpm=[130, 132]),
            sess(distance_yd=[210, 215], tempo_ratio=[2.8, 2.9], hr_bpm=[125, 127]),
            sess(distance_yd=[220, 225], tempo_ratio=[2.9, 3.0], hr_bpm=[120, 122]),
        ]
        result = analyze_trends(sessions)
        self.assertTrue(result["distance_yd"]["trend"]["improving"])   # rising distance
        self.assertTrue(result["hr_bpm"]["trend"]["improving"])         # falling HR
        self.assertTrue(result["tempo_ratio"]["trend"]["improving"])    # toward 3.0

    def test_metric_in_only_one_session_dropped(self):
        sessions = [sess(distance_yd=[200]), sess(tempo_ratio=[3.0])]
        result = analyze_trends(sessions)
        # Neither metric appears in two sessions.
        self.assertNotIn("distance_yd", result)
        self.assertNotIn("tempo_ratio", result)


class TestSlopeAgainstSessionIndex(unittest.TestCase):
    """A session missing the metric must stay a GAP on the x-axis.

    Compacting the values and regressing against their new positions rescales
    the slope, so "per session" would mean something different for every metric
    in the same report.
    """

    def test_a_gap_halves_the_per_session_slope(self):
        # 10 at session 0, 20 at session 2: +5 per session, not +10.
        self.assertAlmostEqual(trends.linear_slope([10.0, 20.0], [0, 2]), 5.0)
        self.assertAlmostEqual(trends.linear_slope([10.0, 20.0]), 10.0)

    def test_direction_is_unchanged_by_the_fix(self):
        # Compaction preserved order, so the sign was always right; this guards
        # against the fix accidentally changing it.
        rising = trends.linear_slope([1.0, 2.0, 3.0], [0, 2, 5])
        falling = trends.linear_slope([3.0, 2.0, 1.0], [0, 2, 5])
        self.assertGreater(rising, 0)
        self.assertLess(falling, 0)

    def test_mismatched_lengths_are_refused_rather_than_guessed(self):
        self.assertIsNone(trends.linear_slope([1.0, 2.0, 3.0], [0, 1]))

    def test_a_metric_absent_from_a_middle_session_still_trends(self):
        sessions = [
            [{"tempo_ratio": 2.0}, {"tempo_ratio": 2.0}],
            [{"peak_g": 9.0}],                                 # no tempo at all
            [{"tempo_ratio": 3.0}, {"tempo_ratio": 3.0}],
        ]
        analysis = trends.analyze_trends(sessions)
        self.assertIn("tempo_ratio", analysis)
        tempo = analysis["tempo_ratio"]
        self.assertEqual(tempo["first"], 2.0)
        self.assertEqual(tempo["last"], 3.0)
        self.assertEqual(tempo["values"], [2.0, None, 3.0])
        # 1.0 of change spread over TWO sessions, not over one step.
        self.assertAlmostEqual(tempo["trend"]["slope"], 0.5)


class TestChipsDoNotContaminateTheDistanceTrend(unittest.TestCase):
    """A chip is a real shot but not a club distance.

    round_report.py excludes short shots from its distance stats and club
    bands. trends.py did not, so the SAME golfer hitting the SAME drives was
    reported as regressing whenever a round happened to include more short game.
    """

    def drives(self, n=10, yards=200.0):
        return [{"distance_yd": yards} for _ in range(n)]

    def chips(self, n=4, yards=20.0):
        return [{"distance_yd": yards, "short_shot": True} for _ in range(n)]

    def test_adding_short_game_does_not_manufacture_a_decline(self):
        # Ten 200 yd drives, twice. The second round also got up and down four
        # times. Nothing about the driving changed.
        analysis = trends.analyze_trends([
            self.drives(),
            self.drives() + self.chips(),
        ])
        distance = analysis["distance_yd"]
        self.assertEqual(distance["values"], [200.0, 200.0])
        self.assertEqual(distance["trend"]["direction"], "flat")

    def test_a_real_decline_is_still_reported(self):
        # The exclusion must not blunt the signal it is protecting.
        analysis = trends.analyze_trends([
            self.drives(yards=220.0) + self.chips(),
            self.drives(yards=190.0) + self.chips(),
        ])
        self.assertEqual(analysis["distance_yd"]["trend"]["direction"], "falling")
        self.assertIs(analysis["distance_yd"]["trend"]["improving"], False)

    def test_a_session_of_nothing_but_chips_has_no_distance_value(self):
        # Not zero, and not the chip average — there is no club distance in it.
        self.assertIsNone(
            trends.session_value(self.chips(), trends.METRICS["distance_yd"])
        )

    def test_swing_metrics_still_include_short_shots(self):
        # A chip has a real tempo and a real impact. Excluding it from those too
        # would discard good data, and would disagree with round_report.py.
        swings = [
            {"distance_yd": 200.0, "peak_g": 10.0},
            {"distance_yd": 20.0, "short_shot": True, "peak_g": 4.0},
        ]
        self.assertEqual(len(trends.usable_swings(swings, trends.METRICS["peak_g"])), 2)
        self.assertEqual(len(trends.usable_swings(swings, trends.METRICS["distance_yd"])), 1)
if __name__ == "__main__":
    unittest.main(verbosity=2)
