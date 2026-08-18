"""Tests for the round report and its WHOOP join.

These are mostly robustness tests. The report is the last thing that runs after
a round, on data shapes nobody controls: WHOOP emits partial records, and a
session may contain one swing, no swings, or swings missing every optional
field. A crash here costs the user the entire analysis of a round they have
already played and cannot replay.
"""

import contextlib
import io
import json
import os
import tempfile
import unittest

import round_report


def render(swings, cache_path=None):
    buffer = io.StringIO()
    with contextlib.redirect_stdout(buffer):
        round_report.report(swings, cache_path)
    return buffer.getvalue()


def swing(index, **fields):
    base = {"index": index, "timestamp": "2026-08-17T14:{:02d}:00".format(index)}
    base.update(fields)
    return base


class TestReportRobustness(unittest.TestCase):
    def test_no_swings_says_so_without_crashing(self):
        self.assertIn("No swings", render([]))

    def test_one_swing_with_nothing_else(self):
        text = render([swing(1)])
        self.assertIn("Round report", text)

    def test_swings_with_no_distances(self):
        text = render([swing(i, peak_g=11.0) for i in range(1, 6)])
        self.assertIn("none", text.lower())

    def test_swings_with_no_tempo(self):
        text = render([swing(i, distance_yd=200.0) for i in range(1, 6)])
        self.assertIn("no readings", text)

    def test_identical_distances_do_not_divide_by_zero(self):
        # Zero variance is the classic crash: cv = stdev / mean, and a spread of
        # exactly zero across identical shots is a real thing on a range.
        text = render([swing(i, distance_yd=150.0) for i in range(1, 8)])
        self.assertIn("150 yd", text)

    def test_a_zero_distance_shot_does_not_break_the_stats(self):
        text = render([swing(1, distance_yd=0.0), swing(2, distance_yd=200.0)])
        self.assertIn("Round report", text)


class TestWhoopJoin(unittest.TestCase):
    """The join must degrade one line at a time, never take the report down."""

    HOUR = 3_600_000

    def cache(self, sleep_score):
        payload = {
            "fetchedAt": "2026-08-17T23:00:00.000Z",
            "cycles": [{
                "id": "c1", "start": "2026-08-17T13:00:00.000Z", "end": None,
                "timezone_offset": "-07:00", "score_state": "SCORED",
                "score": {"strain": 12.4, "kilojoule": 9000,
                          "average_heart_rate": 78, "max_heart_rate": 148},
            }],
            "recoveries": [{
                "cycle_id": "c1", "sleep_id": "s1", "score_state": "SCORED",
                "score": {"recovery_score": 64, "resting_heart_rate": 54,
                          "hrv_rmssd_milli": 61.0},
            }],
            "sleeps": [{
                "id": "s1", "start": "2026-08-17T05:30:00.000Z",
                "end": "2026-08-17T13:00:00.000Z", "timezone_offset": "-07:00",
                "nap": False, "score_state": "SCORED", "score": sleep_score,
            }],
            "workouts": [],
        }
        handle = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
        json.dump(payload, handle)
        handle.close()
        self.addCleanup(os.unlink, handle.name)
        return handle.name

    def swings(self):
        return [swing(i, distance_yd=150.0 + i, peak_g=11.0) for i in range(1, 8)]

    def test_a_complete_sleep_record_reports_hours(self):
        path = self.cache({
            "sleep_performance_percentage": 81,
            "stage_summary": {
                "total_in_bed_time_milli": 8 * self.HOUR,
                "total_awake_time_milli": 1 * self.HOUR,
            },
        })
        self.assertIn("Round report", render(self.swings(), path))

    def test_a_partial_stage_summary_does_not_take_the_report_down(self):
        # WHOOP emits SCORED records whose stage summary is missing fields.
        # Subscripting them raised KeyError and destroyed the whole round
        # analysis over one absent sleep number.
        path = self.cache({
            "sleep_performance_percentage": 81,
            "stage_summary": {"total_in_bed_time_milli": 8 * self.HOUR},
        })
        text = render(self.swings(), path)
        self.assertIn("Round report", text)

    def test_an_empty_stage_summary_is_survivable(self):
        path = self.cache({"sleep_performance_percentage": 81, "stage_summary": {}})
        self.assertIn("Round report", render(self.swings(), path))

    def test_a_null_stage_summary_is_survivable(self):
        path = self.cache({"sleep_performance_percentage": 81, "stage_summary": None})
        self.assertIn("Round report", render(self.swings(), path))

    def test_a_null_score_is_survivable(self):
        # The PENDING_SCORE shape: key present, value null.
        path = self.cache(None)
        self.assertIn("Round report", render(self.swings(), path))

    def test_a_missing_cache_file_is_survivable(self):
        text = render(self.swings(), "/nonexistent/whoop-cache.json")
        self.assertIn("Round report", text)

    def test_a_corrupt_cache_file_is_survivable(self):
        handle = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
        handle.write("{ this is not json")
        handle.close()
        self.addCleanup(os.unlink, handle.name)
        self.assertIn("Round report", render(self.swings(), handle.name))


class TestRoundDate(unittest.TestCase):
    def test_takes_the_first_timestamped_swing(self):
        swings = [swing(1), swing(2)]
        del swings[0]["timestamp"]
        self.assertEqual(round_report.round_date(swings), "2026-08-17")

    def test_no_timestamps_yields_none(self):
        swings = [{"index": 1}, {"index": 2}]
        self.assertIsNone(round_report.round_date(swings))


if __name__ == "__main__":
    unittest.main(verbosity=2)
