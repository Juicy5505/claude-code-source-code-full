"""Tests for swing_metrics, built around synthetic swings of known tempo."""

import math
import unittest

import swing_metrics

from swing_metrics import (
    analyse_swing,
    attitude_sweep,
    consistency,
    fatigue_split,
    find_motion_start,
    find_transition,
    tempo_verdict,
)

HZ = 100.0


def synth_swing(backswing_s=0.9, downswing_s=0.3, quiet_s=1.0, peak_g=11.0,
                with_attitude=False, yaw_deg=90.0):
    """A swing trace with a known tempo, shaped like the real acceleration profile.

    quiet -> backswing ramp -> near-zero at the top -> downswing spike -> decay.
    The transition dip is what the phase finder keys on, so it has to be there.
    """
    samples = []
    t = 0.0

    def push(mag, frac_through=0.0):
        attitude = None
        if with_attitude:
            yaw = math.radians(yaw_deg) * frac_through
            attitude = (0.0, 0.0, yaw)
        samples.append((round(t, 4), mag, attitude))

    n_quiet = int(quiet_s * HZ)
    for _ in range(n_quiet):
        push(0.05)
        t += 1 / HZ

    # Backswing: rises then falls back toward zero at the top.
    n_back = int(backswing_s * HZ)
    for i in range(n_back):
        frac = i / max(1, n_back - 1)
        mag = 2.2 * math.sin(math.pi * frac) + 0.05
        push(mag, frac * 0.6)
        t += 1 / HZ

    # Downswing: sharp ramp into the impact peak.
    n_down = int(downswing_s * HZ)
    for i in range(n_down):
        frac = (i + 1) / n_down
        push(0.1 + (peak_g - 0.1) * (frac ** 2.5), 0.6 + frac * 0.4)
        t += 1 / HZ

    peak_index = len(samples) - 1

    for i in range(int(0.5 * HZ)):  # follow-through decay
        push(peak_g * math.exp(-6.0 * i / HZ), 1.0)
        t += 1 / HZ

    return samples, peak_index


class TestPhaseDetection(unittest.TestCase):
    def test_transition_lands_at_the_top_of_the_backswing(self):
        samples, peak = synth_swing(backswing_s=0.9, downswing_s=0.3)
        transition = find_transition(samples, peak)
        self.assertIsNotNone(transition)
        # The top sits 0.3s before impact, within a couple of samples.
        gap = samples[peak][0] - samples[transition][0]
        self.assertAlmostEqual(gap, 0.3, delta=0.05)

    def test_motion_start_skips_the_quiet_period(self):
        samples, peak = synth_swing(quiet_s=1.0, backswing_s=0.9)
        start = find_motion_start(samples, peak)
        self.assertIsNotNone(start)
        # Motion begins around t=1.0s, after the quiet stretch.
        self.assertGreater(samples[start][0], 0.85)
        self.assertLess(samples[start][0], 1.15)

    def test_no_transition_when_peak_is_first_sample(self):
        samples, _ = synth_swing()
        self.assertIsNone(find_transition(samples, 0))


class TestTempo(unittest.TestCase):
    def assert_tempo(self, backswing_s, downswing_s, expected, delta=0.35):
        samples, peak = synth_swing(backswing_s=backswing_s, downswing_s=downswing_s)
        result = analyse_swing(samples, peak)
        self.assertIsNotNone(result["tempo_ratio"], "tempo not derived")
        self.assertAlmostEqual(result["tempo_ratio"], expected, delta=delta)

    def test_recovers_a_3_to_1_tempo(self):
        self.assert_tempo(0.9, 0.3, 3.0)

    def test_recovers_a_2_to_1_tempo(self):
        self.assert_tempo(0.8, 0.4, 2.0)

    def test_recovers_a_4_to_1_tempo(self):
        self.assert_tempo(1.2, 0.3, 4.0)

    def test_phase_durations_are_reported(self):
        samples, peak = synth_swing(backswing_s=0.9, downswing_s=0.3)
        result = analyse_swing(samples, peak)
        self.assertAlmostEqual(result["backswing_s"], 0.9, delta=0.1)
        self.assertAlmostEqual(result["downswing_s"], 0.3, delta=0.05)

    def test_peak_is_reported_even_when_phases_fail(self):
        result = analyse_swing([(0.0, 7.5, None)])
        self.assertEqual(result["peak_g"], 7.5)
        self.assertIsNone(result["tempo_ratio"])

    def test_empty_window(self):
        self.assertEqual(analyse_swing([]), {})

    def test_peak_index_inferred_when_absent(self):
        samples, peak = synth_swing()
        self.assertAlmostEqual(
            analyse_swing(samples)["peak_g"], samples[peak][1], delta=0.01
        )


class TestVerdict(unittest.TestCase):
    def test_benchmark_band(self):
        self.assertIn("3:1", tempo_verdict(3.0))
        self.assertIn("3:1", tempo_verdict(2.6))

    def test_rushing(self):
        self.assertIn("rushing", tempo_verdict(1.8))

    def test_slow(self):
        self.assertIn("slow", tempo_verdict(4.5))

    def test_no_reading(self):
        self.assertEqual(tempo_verdict(None), "no reading")
        self.assertEqual(tempo_verdict(float("nan")), "no reading")


class TestAttitude(unittest.TestCase):
    def test_sweep_measures_rotation_range(self):
        samples, peak = synth_swing(with_attitude=True, yaw_deg=90.0)
        sweep = attitude_sweep(samples, 0, peak)
        self.assertIsNotNone(sweep)
        self.assertAlmostEqual(sweep["yaw_deg"], 90.0, delta=5.0)

    def test_sweep_is_none_without_attitude_data(self):
        samples, peak = synth_swing(with_attitude=False)
        self.assertIsNone(attitude_sweep(samples, 0, peak))


class TestAcrossRound(unittest.TestCase):
    def test_consistency_reports_spread(self):
        swings = [{"peak_g": v} for v in (10.0, 10.0, 10.0, 10.0)]
        result = consistency(swings, "peak_g")
        self.assertEqual(result["stdev"], 0.0)
        self.assertEqual(result["n"], 4)

    def test_consistency_needs_two_readings(self):
        self.assertIsNone(consistency([{"peak_g": 10.0}], "peak_g"))

    def test_consistency_skips_missing_values(self):
        swings = [{"peak_g": 10.0}, {"peak_g": None}, {"peak_g": 12.0}]
        self.assertEqual(consistency(swings, "peak_g")["n"], 2)

    def test_fatigue_split_detects_late_round_decline(self):
        # 260 yd early, 240 yd late: a clear drop-off.
        swings = [{"distance_yd": v} for v in (260, 258, 262, 240, 238, 242)]
        result = fatigue_split(swings, "distance_yd")
        self.assertIsNotNone(result)
        self.assertLess(result["change"], 0)
        self.assertAlmostEqual(result["change_pct"], -7.7, delta=0.5)

    def test_fatigue_split_flat_round(self):
        swings = [{"distance_yd": 250} for _ in range(8)]
        self.assertEqual(fatigue_split(swings, "distance_yd")["change"], 0.0)

    def test_fatigue_split_needs_enough_shots(self):
        swings = [{"distance_yd": 250} for _ in range(4)]
        self.assertIsNone(fatigue_split(swings, "distance_yd"))




class TestAdaptivePerf(unittest.TestCase):
    def test_cached_median_matches_naive(self):
        from swing_metrics import AdaptiveThreshold
        import random
        random.seed(7)
        det = AdaptiveThreshold(sample_hz=100, recompute_every=25)
        stream = [random.uniform(0.2, 3.0) for _ in range(5000)]
        for i, m in enumerate(stream):
            det.observe(m)
            if i % 25 == 0 and det.window:
                naive = sorted(det.window)
                mid = len(naive) // 2
                expect = naive[mid] if len(naive) % 2 else (naive[mid-1]+naive[mid])/2
                # Cache may be up to recompute_every samples stale; on a
                # recompute tick it must match exactly.
                if det._since_recompute == 0:
                    self.assertAlmostEqual(det.baseline(), expect, places=12)

    def test_still_detects_after_caching(self):
        from swing_metrics import AdaptiveThreshold
        det = AdaptiveThreshold(sample_hz=100)
        for _ in range(600):
            det.observe(1.5)
        self.assertTrue(det.is_swing(12.0))
        self.assertFalse(det.is_swing(2.0))


class TestTourTempoFrames(unittest.TestCase):
    def test_hogan_is_21_7(self):
        from swing_metrics import tour_tempo_frames
        self.assertEqual(tour_tempo_frames(0.70, 0.233), "21/7")

    def test_none_phases(self):
        from swing_metrics import tour_tempo_frames
        self.assertIsNone(tour_tempo_frames(None, 0.3))



class TestNoAddressReturnsNone(unittest.TestCase):
    """A swing with no quiet address must yield tempo None, not fabricated."""

    def test_motion_start_none_without_quiet_run(self):
        from swing_metrics import find_motion_start
        # Continuous motion, never below the quiet threshold: no address.
        samples = [(i / 100.0, 5.0, None) for i in range(300)]
        peak = 250
        self.assertIsNone(find_motion_start(samples, peak))

    def test_tempo_none_for_swing_out_of_motion(self):
        from swing_metrics import analyse_swing
        # Busy the whole window, spike at the end. No quiet lead-in.
        samples = [(i / 100.0, 4.0 + (8.0 if i == 260 else 0.0), None) for i in range(280)]
        result = analyse_swing(samples, 260)
        self.assertEqual(result["peak_g"], 12.0)      # peak still reported
        self.assertIsNone(result["tempo_ratio"])       # tempo honestly absent

    def test_real_swing_still_resolves(self):
        # A proper quiet-then-swing window must still produce a tempo.
        from swing_metrics import analyse_swing
        samples, peak = synth_swing(backswing_s=0.9, downswing_s=0.3, quiet_s=1.0)
        self.assertIsNotNone(analyse_swing(samples, peak)["tempo_ratio"])



class TestAngleUnwrapping(unittest.TestCase):
    """A body turn that crosses the +/-pi yaw boundary must not read as 359 deg."""

    @staticmethod
    def wrapped(theta):
        return math.atan2(math.sin(theta), math.cos(theta))

    def sweep(self, start_rad, step_rad, n):
        samples = [
            (i * 0.01, 1.0, (0.0, 0.0, self.wrapped(start_rad + i * step_rad)))
            for i in range(n)
        ]
        return swing_metrics.attitude_sweep(samples, 0, len(samples) - 1)["yaw_deg"]

    def test_a_turn_crossing_pi_reports_its_real_size(self):
        # 40 samples x 0.02 rad = 0.78 rad = 44.7 deg, crossing pi part way.
        self.assertAlmostEqual(self.sweep(2.9, 0.02, 40), 44.7, delta=0.2)

    def test_a_turn_nowhere_near_the_boundary_is_unchanged(self):
        self.assertAlmostEqual(self.sweep(0.0, 0.02, 40), 44.7, delta=0.2)

    def test_a_turn_crossing_minus_pi_the_other_way(self):
        self.assertAlmostEqual(self.sweep(-2.9, -0.02, 40), 44.7, delta=0.2)

    def test_unwrap_leaves_a_monotonic_sequence_alone(self):
        values = [0.0, 0.1, 0.2, 0.3]
        self.assertEqual(swing_metrics._unwrap(values), values)

    def test_unwrap_handles_empty_and_single_values(self):
        self.assertEqual(swing_metrics._unwrap([]), [])
        self.assertEqual(swing_metrics._unwrap([1.5]), [1.5])


if __name__ == "__main__":
    unittest.main(verbosity=2)
