"""Tests for the phone pre-flight check.

selftest.py exists to catch a broken setup BEFORE a session, so the one thing
it must never do is pass a setup that would in fact record nothing. Each check
is exercised against the failure it is meant to catch, with the device modules
stubbed — the same technique test_swing_ui.py uses.
"""

import importlib
import sys
import types
import unittest


def stub_devices(*, accel=None, fix=None, missing=()):
    """Install fake Pythonista modules with the behaviour a test wants."""
    for name in ("motion", "location", "console", "ui", "sound", "cb"):
        if name in missing:
            sys.modules.pop(name, None)
            continue
        sys.modules[name] = types.ModuleType(name)

    if "motion" not in missing:
        motion = sys.modules["motion"]
        motion.start_updates = lambda: None
        motion.stop_updates = lambda: None
        motion.get_user_acceleration = lambda: accel
        motion.get_attitude = lambda: (0.0, 0.0, 0.0)

    if "location" not in missing:
        loc = sys.modules["location"]
        loc.start_updates = lambda: None
        loc.stop_updates = lambda: None
        loc.get_location = lambda: fix

    if "console" not in missing:
        sys.modules["console"].alert = lambda *a, **k: 1


class SelfTestCase(unittest.TestCase):
    def setUp(self):
        stub_devices(accel=(0.01, 0.02, 0.98),
                     fix={"latitude": 32.9, "longitude": -117.2,
                          "horizontal_accuracy": 5.0})
        # Reimport per test so each picks up the current stubs.
        for module in ("selftest", "swing_logger"):
            sys.modules.pop(module, None)
        self.selftest = importlib.import_module("selftest")
        # Real timeouts make a suite slow enough that people stop running it.
        self.selftest.GPS_TIMEOUT_S = 0.2
        self.selftest.RATE_SAMPLE_S = 0.2

    def run_check(self, name):
        for check_name, fn in self.selftest.CHECKS:
            if check_name == name:
                return fn()
        self.fail(f"no check named {name!r}")


class TestMotionCheck(SelfTestCase):
    def test_passes_when_the_sensor_reports(self):
        self.assertEqual(self.run_check("Motion sensor").status, "ok")

    def test_fails_when_permission_is_denied(self):
        # Denied Motion & Fitness access reads as None, and a session would
        # then detect nothing while appearing to run normally.
        stub_devices(accel=None, fix={"latitude": 1.0, "longitude": 1.0,
                                      "horizontal_accuracy": 5.0})
        result = self.run_check("Motion sensor")
        self.assertEqual(result.status, "fail")
        self.assertIn("Motion & Fitness", result.fix)

    def test_warns_when_every_reading_is_exactly_zero(self):
        stub_devices(accel=(0.0, 0.0, 0.0),
                     fix={"latitude": 1.0, "longitude": 1.0,
                          "horizontal_accuracy": 5.0})
        self.assertEqual(self.run_check("Motion sensor").status, "warn")


class TestGPSCheck(SelfTestCase):
    def gps(self, fix):
        stub_devices(accel=(0.0, 0.0, 1.0), fix=fix)
        return self.run_check("GPS")

    def test_passes_on_a_good_fix(self):
        self.assertEqual(
            self.gps({"latitude": 32.9, "longitude": -117.2,
                      "horizontal_accuracy": 5.0}).status, "ok")

    def test_fails_on_a_negative_accuracy(self):
        # iOS reports a NEGATIVE accuracy for an INVALID fix. Reading that as
        # "excellent" is exactly the trap shot_detect guards against, and the
        # pre-flight must not fall into it either.
        result = self.gps({"latitude": 32.9, "longitude": -117.2,
                           "horizontal_accuracy": -1.0})
        self.assertEqual(result.status, "fail")
        self.assertIn("invalid", result.detail)

    def test_fails_when_accuracy_is_worse_than_the_detector_accepts(self):
        # shot_detect rejects fixes over 20 m, so a 45 m fix records nothing.
        result = self.gps({"latitude": 32.9, "longitude": -117.2,
                           "horizontal_accuracy": 45.0})
        self.assertEqual(result.status, "fail")

    def test_warns_in_the_usable_but_imprecise_band(self):
        self.assertEqual(
            self.gps({"latitude": 32.9, "longitude": -117.2,
                      "horizontal_accuracy": 15.0}).status, "warn")

    def test_the_gps_threshold_matches_the_detector(self):
        # Guards against the two drifting apart: a pre-flight that passes a fix
        # the detector will reject is worse than no pre-flight.
        import shot_detect

        result = self.gps({"latitude": 32.9, "longitude": -117.2,
                           "horizontal_accuracy": shot_detect.MAX_ACCURACY_M + 1})
        self.assertEqual(result.status, "fail")


class TestUploadCheck(SelfTestCase):
    def configure(self, url, token):
        import swing_logger

        swing_logger.INGEST_URL = url
        swing_logger.INGEST_TOKEN = token

    def test_unconfigured_is_a_warning_not_a_failure(self):
        self.configure("", "")
        result = self.run_check("Upload target")
        self.assertEqual(result.status, "warn")
        self.assertIn("stay on the phone", result.fix)

    def test_a_url_without_a_token_fails(self):
        # The server answers 401, and the session is silently never delivered.
        self.configure("http://100.1.2.3:8790", "")
        result = self.run_check("Upload target")
        self.assertEqual(result.status, "fail")
        self.assertIn("401", result.fix)

    def test_a_lan_address_is_called_out(self):
        # Works at home, fails at the course — the failure mode that only shows
        # up when you are somewhere you cannot fix it.
        self.configure("http://192.168.1.24:8790", "tok")
        result = self.run_check("Upload target")
        self.assertIn("tailscale", (result.fix or "").lower())


class TestRunner(SelfTestCase):
    def test_a_broken_check_does_not_stop_the_others(self):
        def explode():
            raise RuntimeError("boom")

        original = list(self.selftest.CHECKS)
        try:
            self.selftest.CHECKS.insert(0, ("Exploding", explode))
            import contextlib
            import io

            buffer = io.StringIO()
            with contextlib.redirect_stdout(buffer):
                self.selftest.main()
            output = buffer.getvalue()
            self.assertIn("Exploding", output)
            self.assertIn("Motion sensor", output)  # later checks still ran
        finally:
            self.selftest.CHECKS[:] = original

    def test_reports_not_ready_when_something_fails(self):
        import contextlib
        import io

        stub_devices(accel=None, fix=None)
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            code = self.selftest.main()
        self.assertEqual(code, 1)
        self.assertIn("NOT READY", buffer.getvalue())

    def test_autolock_is_always_surfaced(self):
        # iOS exposes no API for it, so it can only be stated — and a sleeping
        # screen ends a session silently, which is the commonest way a round is
        # lost. Saying nothing would be worse than an unverifiable warning.
        result = self.run_check("Auto-Lock")
        self.assertEqual(result.status, "warn")
        self.assertIn("Auto-Lock", result.fix)

    def test_whoop_hr_check_points_at_broadcast(self):
        # Kit B (WHOOP + phone) only gets live HR when Broadcast is on. The
        # check must name that switch, not silently pass.
        result = self.run_check("WHOOP HR Broadcast")
        self.assertEqual(result.status, "warn")
        self.assertIn("HR Broadcast", result.fix)


if __name__ == "__main__":
    unittest.main(verbosity=2)
