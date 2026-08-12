"""Tests for shot_model. Runs anywhere — no Pythonista needed."""

import math
import unittest

from shot_model import (
    carry_m,
    fit_swings,
    haversine_m,
    linear_fit,
    metres_to_yards,
    predict_distance,
    shot_distances,
    simulate,
    solve_launch_speed,
    trajectory_for_distance,
)


class TestGeometry(unittest.TestCase):
    def test_one_degree_of_latitude(self):
        # One degree of latitude is R * pi / 180 regardless of longitude.
        expected = 6_371_008.8 * math.pi / 180
        self.assertAlmostEqual(haversine_m(0, 0, 1, 0), expected, delta=1.0)

    def test_zero_distance(self):
        self.assertAlmostEqual(haversine_m(32.9, -117.2, 32.9, -117.2), 0.0, places=6)

    def test_known_short_hop(self):
        # ~250 yards north at San Diego latitude.
        metres = haversine_m(32.9, -117.2, 32.9 + 228.6 / 111_195, -117.2)
        self.assertAlmostEqual(metres_to_yards(metres), 250.0, delta=1.0)

    def test_symmetry(self):
        a = haversine_m(32.9, -117.2, 33.1, -117.4)
        b = haversine_m(33.1, -117.4, 32.9, -117.2)
        self.assertAlmostEqual(a, b, places=9)


class TestShotDistances(unittest.TestCase):
    def loc(self, lat, lon):
        return {"latitude": lat, "longitude": lon}

    def test_consecutive_swings_measure_the_shot(self):
        swings = [
            {"peak_g": 9.0, "location": self.loc(32.9, -117.2)},
            {"peak_g": 8.0, "location": self.loc(32.9 + 228.6 / 111_195, -117.2)},
        ]
        shot_distances(swings)
        self.assertAlmostEqual(swings[0]["distance_yd"], 250.0, delta=1.5)

    def test_final_swing_has_no_successor(self):
        swings = [{"peak_g": 9.0, "location": self.loc(32.9, -117.2)}]
        shot_distances(swings)
        self.assertIsNone(swings[0]["distance_yd"])

    def test_missing_gps_yields_none_not_a_crash(self):
        swings = [
            {"peak_g": 9.0, "location": None},
            {"peak_g": 8.0, "location": self.loc(32.9, -117.2)},
            {"peak_g": 7.0, "location": {"latitude": None, "longitude": None}},
        ]
        shot_distances(swings)
        self.assertIsNone(swings[0]["distance_yd"])
        self.assertIsNone(swings[1]["distance_yd"])


class TestFitting(unittest.TestCase):
    def test_recovers_a_known_line(self):
        xs = [1, 2, 3, 4, 5]
        ys = [3 * x + 10 for x in xs]
        fit = linear_fit(xs, ys)
        self.assertAlmostEqual(fit["slope"], 3.0, places=9)
        self.assertAlmostEqual(fit["intercept"], 10.0, places=9)
        self.assertAlmostEqual(fit["r2"], 1.0, places=9)

    def test_too_few_points(self):
        self.assertIsNone(linear_fit([1, 2], [3, 4]))

    def test_zero_variance_is_undefined_not_zero(self):
        self.assertIsNone(linear_fit([5, 5, 5], [1, 2, 3]))

    def test_fit_swings_ignores_putts_and_unmeasured(self):
        swings = [
            {"peak_g": 10.0, "distance_yd": 250.0},
            {"peak_g": 8.0, "distance_yd": 200.0},
            {"peak_g": 6.0, "distance_yd": 150.0},
            {"peak_g": 2.0, "distance_yd": 4.0},     # a putt — excluded
            {"peak_g": 9.0, "distance_yd": None},    # unmeasured — excluded
        ]
        fit = fit_swings(swings)
        self.assertEqual(fit["n"], 3)
        self.assertAlmostEqual(fit["slope"], 25.0, places=6)

    def test_predict_uses_the_fit(self):
        fit = {"slope": 25.0, "intercept": 0.0, "r2": 1.0, "n": 5}
        self.assertAlmostEqual(predict_distance(fit, 8.0), 200.0, places=6)

    def test_predict_never_returns_negative(self):
        fit = {"slope": 25.0, "intercept": -500.0, "r2": 1.0, "n": 5}
        self.assertEqual(predict_distance(fit, 1.0), 0.0)

    def test_predict_without_fit(self):
        self.assertIsNone(predict_distance(None, 8.0))


class TestBallFlight(unittest.TestCase):
    def test_trajectory_starts_and_lands_at_ground(self):
        path = simulate(60.0, 13.0)
        self.assertEqual(path[0], (0.0, 0.0))
        self.assertAlmostEqual(path[-1][1], 0.0, places=6)
        self.assertGreater(path[-1][0], 0.0)

    def test_ball_actually_gets_airborne(self):
        path = simulate(60.0, 13.0)
        self.assertGreater(max(y for _, y in path), 5.0)

    def test_carry_increases_with_speed(self):
        self.assertLess(carry_m(40.0, 13.0), carry_m(60.0, 13.0))
        self.assertLess(carry_m(60.0, 13.0), carry_m(75.0, 13.0))

    def test_drag_shortens_flight_versus_vacuum(self):
        speed, angle = 70.0, 13.0
        vacuum = speed ** 2 * math.sin(2 * math.radians(angle)) / 9.80665
        self.assertLess(carry_m(speed, angle), vacuum)

    def test_solver_hits_its_target(self):
        for target_m in (100.0, 160.0, 210.0):
            speed = solve_launch_speed(target_m, 13.0)
            self.assertIsNotNone(speed)
            self.assertAlmostEqual(carry_m(speed, 13.0), target_m, delta=1.0)

    def test_solver_rejects_unreachable_distance(self):
        self.assertIsNone(solve_launch_speed(50_000.0, 13.0))

    def test_a_300_yard_drive_is_reachable(self):
        # Drag-only physics puts this out of reach at any sane speed, which is
        # how the missing lift term was caught. It must stay reachable.
        path, speed = trajectory_for_distance(300.0)
        self.assertIsNotNone(path)
        self.assertLess(speed * 2.23694, 210.0)


class TestAgainstRealGolf(unittest.TestCase):
    """Benchmarks against published golf numbers.

    The internal-consistency tests above all passed while the model was badly
    wrong — it was monotonic, the solver converged, and drag beat vacuum, but a
    250 yd carry demanded 250 mph. These pin the model to reality instead.
    """

    def ball_speed_mph(self, carry_yd):
        _, speed = trajectory_for_distance(carry_yd)
        return speed * 2.23694

    def test_driver_ball_speeds_are_realistic(self):
        # A 250 yd carry runs about 155-170 mph of ball speed in the real game.
        self.assertGreater(self.ball_speed_mph(250.0), 150.0)
        self.assertLess(self.ball_speed_mph(250.0), 175.0)

    def test_mid_iron_ball_speed_is_realistic(self):
        # ~200 yd carry sits near 130-145 mph.
        self.assertGreater(self.ball_speed_mph(200.0), 128.0)
        self.assertLess(self.ball_speed_mph(200.0), 148.0)

    def test_driver_apex_is_realistic(self):
        # A 250 yd drive peaks around 80-110 ft (roughly 27-37 yards).
        path, _ = trajectory_for_distance(250.0)
        apex_yd = metres_to_yards(max(y for _, y in path))
        self.assertGreater(apex_yd, 25.0)
        self.assertLess(apex_yd, 40.0)

    def test_lift_materially_extends_carry(self):
        # Backspin should roughly double carry versus a spinless ball.
        spinning = carry_m(67.0, 13.0)
        spinless = carry_m(67.0, 13.0, spin_rpm=0.0)
        self.assertGreater(spinning, spinless * 1.5)

    def test_trajectory_for_distance_matches_measured_yards(self):
        for yards in (120.0, 180.0, 250.0):
            path, speed = trajectory_for_distance(yards)
            self.assertIsNotNone(path)
            self.assertAlmostEqual(metres_to_yards(path[-1][0]), yards, delta=1.5)
            self.assertGreater(speed, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
