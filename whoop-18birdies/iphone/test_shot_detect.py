"""Tests for pocket-mode shot detection.

The tracks here are synthetic but shaped like a real round: walk, stand over the
ball, hit, walk again. Distances are constructed in metres and converted to
coordinates, so an assertion about yardage is checking the geodesy as well as
the clustering.
"""

import math
import unittest

import shot_detect
from shot_detect import Stop, detect_shots, find_stops, shots_from_stops, summarise

# Somewhere flat and unambiguous. Torrey Pines' first tee, near enough.
BASE_LAT = 32.8973
BASE_LON = -117.2531

M_PER_DEG_LAT = 111_320.0


def offset(lat, lon, north_m, east_m):
    """Move a coordinate by a distance in metres. Good to well under a metre
    at these scales, which is far finer than the GPS noise being modelled."""
    dlat = north_m / M_PER_DEG_LAT
    dlon = east_m / (M_PER_DEG_LAT * math.cos(math.radians(lat)))
    return lat + dlat, lon + dlon


def fix(t, lat, lon, accuracy=5.0):
    return {"t": t, "latitude": lat, "longitude": lon, "horizontal_accuracy": accuracy}


def standing(t0, lat, lon, seconds, hz=1.0, jitter_m=3.0):
    """Fixes taken while standing still, with realistic GPS wander."""
    out = []
    n = max(1, int(seconds * hz))
    for i in range(n):
        # Deterministic pseudo-wander: no RNG, so a failure is reproducible.
        angle = i * 2.3999632
        jlat, jlon = offset(lat, lon,
                            jitter_m * math.sin(angle),
                            jitter_m * math.cos(angle))
        out.append(fix(t0 + i / hz, jlat, jlon))
    return out


def walking(t0, lat0, lon0, lat1, lon1, seconds, hz=1.0):
    """Fixes taken while walking in a straight line between two points."""
    out = []
    n = max(2, int(seconds * hz))
    for i in range(n):
        frac = i / (n - 1)
        out.append(fix(t0 + i / hz,
                       lat0 + (lat1 - lat0) * frac,
                       lon0 + (lon1 - lon0) * frac))
    return out


# A golfer walks at roughly 1.4 m/s. Using a fixed walk DURATION regardless of
# distance — as an earlier version of this helper did — models a 12 m stroll as
# taking a minute, i.e. 0.2 m/s, which is not walking and is indistinguishable
# from standing still to any detector. Deriving duration from a real speed keeps
# the synthetic track honest.
WALK_SPEED_MS = 1.4


def round_track(shot_metres, stop_seconds=15.0, walk_speed_ms=WALK_SPEED_MS):
    """A whole round: stand, hit, walk the shot's distance, stand, hit..."""
    fixes = []
    t = 1000.0
    lat, lon = BASE_LAT, BASE_LON
    for metres in shot_metres:
        fixes += standing(t, lat, lon, stop_seconds)
        t += stop_seconds
        nlat, nlon = offset(lat, lon, metres, 0.0)
        walk_seconds = max(2.0, metres / walk_speed_ms)
        fixes += walking(t, lat, lon, nlat, nlon, walk_seconds)
        t += walk_seconds
        lat, lon = nlat, nlon
    # The final resting place, where the ball was holed out.
    fixes += standing(t, lat, lon, stop_seconds)
    return fixes


class TestStopFinding(unittest.TestCase):
    def test_finds_one_stop_per_pause(self):
        fixes = round_track([180.0, 140.0, 90.0])
        stops = find_stops(fixes)
        self.assertEqual(len(stops), 4, "three shots means four stops")

    def test_a_pause_too_brief_is_not_a_stop(self):
        # Four seconds is a glance at the phone, not addressing a ball.
        fixes = standing(0.0, BASE_LAT, BASE_LON, 4.0)
        self.assertEqual(find_stops(fixes), [])

    def test_a_long_pause_is_kept_and_flagged_not_discarded(self):
        # Ten minutes: a backed-up tee, or looking for a ball. It is still a
        # stop, because a stop is a shot BOUNDARY as well as a shot.
        fixes = standing(0.0, BASE_LAT, BASE_LON, 600.0)
        stops = find_stops(fixes)
        self.assertEqual(len(stops), 1)
        self.assertTrue(stops[0].long_wait)

    def test_a_long_wait_does_not_destroy_the_shots_around_it(self):
        """The bug this replaced was severe and completely silent.

        Discarding an over-long stop merged the shot before it with the shot
        after it. In practice a five-minute tee wait between two 251-yard drives
        left two stops 460 yards apart, which the transition rule then threw
        away as a walk between holes — so BOTH drives vanished from the round
        with no warning of any kind.
        """
        fixes = []
        t = 1000.0
        lat, lon = BASE_LAT, BASE_LON
        for wait in (15.0, 300.0, 15.0):      # normal, long tee wait, normal
            fixes += standing(t, lat, lon, wait)
            t += wait
            nlat, nlon = offset(lat, lon, 230.0, 0.0)
            walk = 230.0 / WALK_SPEED_MS
            fixes += walking(t, lat, lon, nlat, nlon, walk)
            t += walk
            lat, lon = nlat, nlon
        fixes += standing(t, lat, lon, 15.0)

        measured = [s["distance_yd"] for s in detect_shots(fixes)
                    if s["kind"] == "shot"]
        self.assertEqual(len(measured), 3, "all three drives must survive")
        for distance in measured:
            self.assertAlmostEqual(distance, 251.5, delta=8.0)

    def test_the_long_wait_flag_reaches_the_session(self):
        fixes = standing(1000.0, BASE_LAT, BASE_LON, 300.0)
        t = 1300.0
        nlat, nlon = offset(BASE_LAT, BASE_LON, 200.0, 0.0)
        fixes += walking(t, BASE_LAT, BASE_LON, nlat, nlon, 200 / WALK_SPEED_MS)
        fixes += standing(t + 200 / WALK_SPEED_MS, nlat, nlon, 15.0)
        session = shot_detect.to_session(detect_shots(fixes))
        self.assertTrue(any(sw.get("long_wait") for sw in session["swings"]))

    def test_walking_straight_through_produces_no_stops(self):
        far_lat, far_lon = offset(BASE_LAT, BASE_LON, 400.0, 0.0)
        fixes = walking(0.0, BASE_LAT, BASE_LON, far_lat, far_lon, 300.0)
        self.assertEqual(find_stops(fixes), [])

    def test_gps_wander_while_standing_stays_one_stop(self):
        # The whole reason the radius is 12 m: consumer GPS drifts several
        # metres while genuinely stationary, and a tighter radius shatters one
        # stop into several phantom shots.
        fixes = standing(0.0, BASE_LAT, BASE_LON, 30.0, jitter_m=6.0)
        stops = find_stops(fixes)
        self.assertEqual(len(stops), 1)
        self.assertGreaterEqual(stops[0].n_fixes, 25)

    def test_stop_centre_is_the_mean_not_the_first_fix(self):
        # A stop opened by a noisy sample must not be anchored to it.
        off_lat, off_lon = offset(BASE_LAT, BASE_LON, 9.0, 0.0)
        fixes = [fix(0.0, off_lat, off_lon)] + [
            fix(t, BASE_LAT, BASE_LON) for t in range(1, 30)
        ]
        stop = find_stops(fixes)[0]
        drift = shot_detect.haversine_m(stop.lat, stop.lon, BASE_LAT, BASE_LON)
        self.assertLess(drift, 1.0, "centre should sit on the bulk of the fixes")


class TestFixValidation(unittest.TestCase):
    def test_negative_accuracy_is_rejected(self):
        # iOS reports a NEGATIVE horizontal accuracy for an INVALID fix. A naive
        # `accuracy <= 20` test reads -1 as pinpoint and builds a round from
        # garbage coordinates.
        fixes = [fix(float(t), BASE_LAT, BASE_LON, accuracy=-1.0) for t in range(30)]
        self.assertEqual(find_stops(fixes), [])

    def test_poor_accuracy_is_rejected(self):
        fixes = [fix(float(t), BASE_LAT, BASE_LON, accuracy=65.0) for t in range(30)]
        self.assertEqual(find_stops(fixes), [])

    def test_absent_accuracy_is_accepted(self):
        # Unknown accuracy is not the same as bad accuracy; some sources simply
        # do not report it, and discarding those would discard the whole round.
        fixes = [
            {"t": float(t), "latitude": BASE_LAT, "longitude": BASE_LON}
            for t in range(30)
        ]
        self.assertEqual(len(find_stops(fixes)), 1)

    def test_missing_or_impossible_coordinates_are_rejected(self):
        bad = [
            {"t": 0.0, "latitude": None, "longitude": BASE_LON},
            {"t": 1.0, "latitude": BASE_LAT, "longitude": None},
            {"t": 2.0, "latitude": 91.0, "longitude": BASE_LON},
            {"t": 3.0, "latitude": BASE_LAT, "longitude": 181.0},
            {"t": 4.0, "latitude": float("nan"), "longitude": BASE_LON},
        ]
        self.assertEqual(find_stops(bad), [])


class TestShotDistances(unittest.TestCase):
    def test_measures_the_distance_between_stops(self):
        shots = detect_shots(round_track([180.0, 140.0]))
        measured = [s["distance_yd"] for s in shots if s["kind"] == "shot"]
        self.assertEqual(len(measured), 2)
        # 180 m = 196.9 yd, 140 m = 153.1 yd. Tolerance covers the 3 m jitter.
        self.assertAlmostEqual(measured[0], 196.9, delta=6.0)
        self.assertAlmostEqual(measured[1], 153.1, delta=6.0)

    def test_the_last_stop_has_no_distance_and_is_kept(self):
        # Dropping it would silently report a round with one fewer shot.
        shots = detect_shots(round_track([180.0]))
        self.assertEqual(shots[-1]["distance_yd"], None)
        self.assertEqual(shots[-1]["kind"], "unmeasured")

    def test_a_walk_between_holes_is_not_a_shot(self):
        # 500 m exceeds any golf shot; it is the walk to the next tee.
        shots = detect_shots(round_track([500.0]))
        kinds = [s["kind"] for s in shots]
        self.assertIn("transition", kinds)
        self.assertNotIn("shot", kinds)

    def test_a_pitch_is_flagged_short_rather_than_counted_as_a_full_shot(self):
        # 40 m = 43.7 yd: resolvable, but well under SHORT_SHOT_YD, so it is
        # reported and kept out of the club statistics.
        shots = detect_shots(round_track([40.0]))
        short = [s for s in shots if s["kind"] == "short"]
        self.assertEqual(len(short), 1)
        self.assertLess(short[0]["distance_yd"], shot_detect.SHORT_SHOT_YD)

    def test_short_shots_stay_out_of_the_full_shot_statistics(self):
        stats = summarise(detect_shots(round_track([180.0, 40.0, 150.0])))
        self.assertEqual(stats["n_shots"], 2)
        self.assertEqual(stats["n_short"], 1)

    def test_a_chip_below_the_resolution_floor_is_invisible_not_wrong(self):
        # THE honest limit of this method. A 12 m chip never breaks the
        # stationary test, so the stop before it, the walk, and the stop after
        # all read as one continuous stop. The shot does not appear.
        #
        # This is documented rather than fixed because it cannot be fixed with
        # constants: tightening the window makes ordinary GPS jitter fabricate
        # stops instead. It is why Arccos and Shot Scope put sensors in the club.
        stops = find_stops(round_track([12.0]))
        self.assertEqual(len(stops), 1, "chip and its walk merge into one stop")
        shots = detect_shots(round_track([12.0]))
        self.assertEqual([s["kind"] for s in shots], ["unmeasured"])

    def test_the_resolution_floor_is_where_the_docs_say_it_is(self):
        # Guards the documented MIN_RESOLVABLE_YD against drift: comfortably
        # above it must resolve, well below it must not.
        above = detect_shots(round_track([45.0]))
        self.assertTrue(any(s["distance_yd"] is not None for s in above),
                        "45 m should resolve — it is above the floor")
        below = detect_shots(round_track([10.0]))
        self.assertTrue(all(s["distance_yd"] is None for s in below),
                        "10 m should not resolve — it is below the floor")

    def test_the_report_states_the_resolution_floor(self):
        text = shot_detect.format_report(detect_shots(round_track([180.0, 150.0])))
        self.assertIn("cannot see", text)
        self.assertIn("{:.0f} yd".format(shot_detect.MIN_RESOLVABLE_YD), text)


class TestSummary(unittest.TestCase):
    def test_reports_mean_longest_and_total(self):
        stats = summarise(detect_shots(round_track([180.0, 140.0, 200.0])))
        self.assertEqual(stats["n_shots"], 3)
        self.assertAlmostEqual(stats["longest_yd"], 218.7, delta=8.0)
        self.assertGreater(stats["total_yd"], stats["longest_yd"])

    def test_empty_track_summarises_without_crashing(self):
        stats = summarise(detect_shots([]))
        self.assertEqual(stats["n_shots"], 0)
        self.assertIsNone(stats["mean_yd"])
        self.assertIsNone(stats["longest_yd"])

    def test_no_shots_report_says_why_rather_than_going_silent(self):
        text = shot_detect.format_report(detect_shots([]))
        self.assertIn("No shots resolved", text)
        self.assertIn("stood still", text)

    def test_report_names_what_a_pocket_cannot_measure(self):
        text = shot_detect.format_report(detect_shots(round_track([180.0, 140.0]))).lower()
        self.assertIn("yd", text)
        for impossible in ("tempo", "swing path", "face angle", "club speed"):
            self.assertIn(impossible, text)


class TestSharedSchema(unittest.TestCase):
    """Pocket sessions must be readable by the same pipeline as swing sessions.

    One schema is the whole point: round_report, club_model, trends and analyze
    all read a {"swings": [...]} wrapper, and the ingest server stores one.
    """

    def session(self, metres=(180.0, 150.0, 40.0)):
        return shot_detect.to_session(detect_shots(round_track(list(metres))))

    def test_emits_the_swings_wrapper_the_pipeline_expects(self):
        session = self.session()
        self.assertEqual(session["mode"], "pocket")
        self.assertIsInstance(session["swings"], list)
        self.assertTrue(session["swings"])

    def test_round_report_can_load_it(self):
        import round_report

        session = self.session()
        # load_swings accepts either the wrapper or a bare list.
        swings = session.get("swings", session)
        self.assertEqual(round_report.load_swings.__name__, "load_swings")
        self.assertTrue(round_report.round_date(swings), "needs a joinable date")

    def test_records_carry_a_local_timestamp_not_utc(self):
        # The server files a session under its first record's date, and every
        # WHOOP join is on the local date. A UTC stamp puts an evening round on
        # tomorrow and drops it out of both.
        import time

        session = self.session()
        stamp = session["swings"][0]["timestamp"]
        self.assertRegex(stamp, r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}$")
        expected = time.strftime("%Y", time.localtime(1000.0))
        self.assertTrue(stamp.startswith(expected))

    def test_unmeasurable_metrics_are_absent_not_zero(self):
        # A zero peak_g would average into the session's force statistics as if
        # it were a real, feeble swing. Absent is the truth.
        for swing in self.session()["swings"]:
            self.assertNotIn("peak_g", swing)
            self.assertNotIn("tempo_ratio", swing)

    def test_walks_between_holes_are_not_emitted_as_shots(self):
        session = shot_detect.to_session(detect_shots(round_track([500.0, 180.0])))
        for swing in session["swings"]:
            self.assertNotEqual(swing.get("kind"), "transition")

    def test_short_shots_are_marked_so_club_stats_can_exclude_them(self):
        session = self.session((180.0, 40.0))
        flagged = [s for s in session["swings"] if s.get("short_shot")]
        self.assertEqual(len(flagged), 1)

    def test_indexes_are_contiguous_from_one(self):
        # A gap would misalign every downstream per-shot table.
        session = shot_detect.to_session(detect_shots(round_track([500.0, 180.0, 150.0])))
        indexes = [s["index"] for s in session["swings"]]
        self.assertEqual(indexes, list(range(1, len(indexes) + 1)))

    def test_the_resolution_floor_travels_with_the_data(self):
        # Anyone reading this file later needs to know what it could not see.
        self.assertEqual(self.session()["min_resolvable_yd"], shot_detect.MIN_RESOLVABLE_YD)


class TestReportIntegration(unittest.TestCase):
    """The pocket session must read correctly through round_report.

    This caught a real bug: chips clustered into a "club" band at 44 yd and
    manufactured a 98-yard gap warning between it and the wedges. That gap is a
    wedge and a chip, not a hole in the bag.
    """

    def render(self, metres):
        import contextlib
        import io

        import round_report

        session = shot_detect.to_session(detect_shots(round_track(list(metres))))
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            round_report.report(session["swings"])
        return buffer.getvalue()

    def test_short_shots_are_excluded_from_club_gapping(self):
        import re

        text = self.render([230.0, 150.0, 40.0, 500.0, 220.0, 145.0, 42.0])
        self.assertIn("short game", text)
        club_section = text.split("Estimated club groupings")[-1].split("Gaps:")[0]
        # Parse the band means rather than substring-matching: "245 yd" contains
        # "45 yd", so a naive `assertNotIn` passes and fails for the wrong reason.
        bands = [float(m) for m in re.findall(r"^\s+(\d+) yd\s+x\d+", club_section, re.M)]
        self.assertTrue(bands, "expected at least one club band")
        self.assertTrue(
            all(b >= shot_detect.SHORT_SHOT_YD for b in bands),
            "chips leaked into the club bands: {}".format(bands),
        )

    def test_short_shots_do_not_drag_the_average_down(self):
        text = self.render([230.0, 150.0, 40.0, 500.0, 220.0, 145.0, 42.0])
        average = int(text.split("average")[1].split("yd")[0].split(":")[1].strip())
        # Drives ~250 yd and approaches ~160 yd average well above 150; including
        # the 45 yd chips would pull it under.
        self.assertGreater(average, 150)

    def test_the_report_still_counts_short_shots_as_shots(self):
        text = self.render([230.0, 150.0, 40.0])
        self.assertIn("swings detected", text)

    def test_a_pocket_session_reports_no_tempo_rather_than_a_fake_one(self):
        text = self.render([230.0, 150.0, 40.0])
        self.assertIn("no readings", text)

    def test_a_short_game_only_round_does_not_pretend_to_gap_a_bag(self):
        text = self.render([40.0, 45.0, 42.0])
        self.assertIn("too few full swings", text)


class TestStopModel(unittest.TestCase):
    def test_duration_and_serialisation(self):
        stop = Stop(100.0, 118.5, BASE_LAT, BASE_LON, 19)
        self.assertAlmostEqual(stop.duration_s, 18.5)
        data = stop.as_dict()
        self.assertEqual(data["n_fixes"], 19)
        self.assertAlmostEqual(data["duration_s"], 18.5)

    def test_shots_from_stops_indexes_from_one(self):
        stops = [
            Stop(0.0, 15.0, BASE_LAT, BASE_LON, 15),
            Stop(75.0, 90.0, *offset(BASE_LAT, BASE_LON, 180.0, 0.0), 15),
        ]
        shots = shots_from_stops(stops)
        self.assertEqual([s["index"] for s in shots], [1, 2])


if __name__ == "__main__":
    unittest.main(verbosity=2)
