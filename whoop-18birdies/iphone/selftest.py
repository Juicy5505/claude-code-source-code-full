"""Check the phone is actually ready, before you drive to the course.

Run this in Pythonista once, on the practice green or in the garden. It takes
about thirty seconds and answers the only question that matters before a
session: **if I start the logger now, will it record anything?**

    python selftest.py

Every failure mode this checks has already happened to somebody: motion
permission never granted, location set to "While Using" but precise location
off, a sample rate too low for tempo, an ingest URL pointing at a LAN address
that stopped working the moment they left the house. Each one produces a
session that looks fine while it runs and is empty or useless afterwards.

It changes nothing and writes nothing. Safe to run any time.
"""

import sys
import time

CHECKS = []

# How long to wait for a first GPS fix. A real cold start under open sky takes
# a few seconds; twelve is generous without making someone stand around. Module
# level so the tests can shorten it — a suite that waits out real timeouts stops
# being run.
GPS_TIMEOUT_S = 12.0

# How long to measure the achieved sample rate over.
RATE_SAMPLE_S = 2.0


def check(name):
    def register(fn):
        CHECKS.append((name, fn))
        return fn

    return register


class Result:
    """A check's outcome: pass, warn (usable but degraded), or fail."""

    def __init__(self, status, detail, fix=None):
        self.status = status
        self.detail = detail
        self.fix = fix


def ok(detail):
    return Result("ok", detail)


def warn(detail, fix=None):
    return Result("warn", detail, fix)


def fail(detail, fix=None):
    return Result("fail", detail, fix)


# --- the checks --------------------------------------------------------------


@check("Pythonista modules")
def _modules():
    missing = []
    for name in ("motion", "location", "console"):
        try:
            __import__(name)
        except ImportError:
            missing.append(name)
    if missing:
        return fail(
            "missing: {}".format(", ".join(missing)),
            "These only exist inside Pythonista. Run this from Pythonista on the "
            "phone, not from a Mac.",
        )
    return ok("motion, location, console all present")


@check("Motion sensor")
def _motion():
    import motion

    motion.start_updates()
    try:
        time.sleep(0.4)
        readings = [motion.get_user_acceleration() for _ in range(10)]
    finally:
        motion.stop_updates()

    if all(r is None for r in readings):
        return fail(
            "no readings",
            "Settings → Privacy & Security → Motion & Fitness → Pythonista: on.",
        )
    # All-zero across a tenth of a second means the sensor is reporting but the
    # values are not real — the phone is being held, so something is non-zero.
    if all(r == (0.0, 0.0, 0.0) for r in readings if r):
        return warn(
            "readings are all exactly zero",
            "Pick the phone up and run this again. If it stays zero, motion "
            "access is being denied silently.",
        )
    peak = max(
        (x * x + y * y + z * z) ** 0.5 for x, y, z in (r for r in readings if r)
    )
    return ok("reading, peak {:.2f} g while held".format(peak))


@check("Sample rate")
def _rate():
    import motion

    from swing_logger import TARGET_HZ, PacedLoop, magnitude

    motion.start_updates()
    try:
        time.sleep(0.3)
        pacer = PacedLoop(TARGET_HZ)
        started = time.time()
        samples = 0
        while time.time() - started < RATE_SAMPLE_S:
            magnitude(motion.get_user_acceleration())
            samples += 1
            pacer.wait()
    finally:
        motion.stop_updates()

    achieved = samples / max(1e-6, time.time() - started)
    if achieved < 40:
        return fail(
            "{:.0f} Hz (target {:.0f})".format(achieved, TARGET_HZ),
            "Too slow to resolve a downswing, which lasts about a quarter of a "
            "second. Close other apps and try again.",
        )
    if achieved < TARGET_HZ * 0.7:
        return warn(
            "{:.0f} Hz (target {:.0f})".format(achieved, TARGET_HZ),
            "Usable for detection; tempo will be coarser than it should be.",
        )
    return ok("{:.0f} Hz".format(achieved))


@check("GPS")
def _gps():
    import location

    location.start_updates()
    try:
        fix = None
        deadline = time.time() + GPS_TIMEOUT_S
        while time.time() < deadline:
            fix = location.get_location()
            if fix and fix.get("latitude") is not None:
                break
            time.sleep(min(0.5, GPS_TIMEOUT_S / 8))
    finally:
        location.stop_updates()

    if not fix or fix.get("latitude") is None:
        return fail(
            "no fix in {:.0f} s".format(GPS_TIMEOUT_S),
            "Settings → Privacy & Security → Location Services → Pythonista → "
            "While Using the App, and turn Precise Location ON. Then step "
            "outside — indoors can genuinely fail.",
        )

    accuracy = fix.get("horizontal_accuracy")
    if accuracy is None:
        return warn("fix with no accuracy figure", "Unusual, but usable.")
    # iOS reports a NEGATIVE accuracy for an invalid fix.
    if accuracy < 0:
        return fail(
            "fix reports accuracy {:.0f} — invalid".format(accuracy),
            "A negative accuracy means iOS could not resolve a position.",
        )
    if accuracy > 20:
        return fail(
            "accuracy {:.0f} m".format(accuracy),
            "Pocket mode rejects fixes worse than 20 m, so this would record "
            "nothing. Precise Location may be off, or you are indoors.",
        )
    if accuracy > 10:
        return warn(
            "accuracy {:.0f} m".format(accuracy),
            "Usable, but shot distances will be several yards out. Better in "
            "the open.",
        )
    return ok("accuracy {:.0f} m".format(accuracy))


@check("Auto-Lock")
def _autolock():
    # iOS gives no API for the Auto-Lock setting, so this cannot be measured —
    # only stated. Saying nothing would be worse: a screen that sleeps ends the
    # session silently, and it is the single most common way a round is lost.
    return warn(
        "cannot be checked from code",
        "Settings → Display & Brightness → Auto-Lock → Never. iOS stops "
        "delivering motion and location the moment the screen sleeps, and the "
        "session just stops with no error.",
    )


@check("Upload target")
def _upload():
    from swing_logger import INGEST_TOKEN, INGEST_URL

    if not INGEST_URL:
        return warn(
            "not configured",
            "Fine — sessions stay on the phone. Set INGEST_URL in "
            "swing_logger.py to have them reach your Mac automatically.",
        )
    if not INGEST_TOKEN:
        return fail(
            "URL set but no token",
            "The server will answer 401. Set INGEST_TOKEN to the value of "
            "WB_INGEST_TOKEN on the Mac.",
        )

    host = INGEST_URL.split("//")[-1].split("/")[0].split(":")[0]
    if host.startswith("192.168.") or host.startswith("10.") or host == "localhost":
        note = (
            "This is a LAN address, so uploads work at home and fail at the "
            "course. Use the Mac's tailnet address (`tailscale ip -4`) instead."
        )
    else:
        note = None

    try:
        import requests
    except ImportError:
        return warn("cannot test — `requests` unavailable in Pythonista", note)

    url = INGEST_URL.rstrip("/").removesuffix("/swings") + "/health"
    try:
        res = requests.get(url, timeout=6)
    except Exception as exc:
        return fail(
            "unreachable ({})".format(exc),
            note or "Is `wb serve` running on the Mac, and are both devices on "
            "the same network or tailnet?",
        )
    if res.status_code != 200:
        return fail("HTTP {} from {}".format(res.status_code, url), note)
    return ok("server reachable at {}".format(host)) if not note else warn(
        "reachable at {}".format(host), note
    )


@check("Analysis modules")
def _modules_import():
    try:
        import shot_detect  # noqa: F401
        import shot_model  # noqa: F401
        import swing_metrics  # noqa: F401
    except ImportError as exc:
        return fail(
            str(exc),
            "Copy ALL the .py files from iphone/ into the same Pythonista "
            "folder — the logger imports its analysis from them.",
        )
    return ok("swing_metrics, shot_model, shot_detect all import")


# --- runner -------------------------------------------------------------------


MARK = {"ok": "PASS", "warn": "WARN", "fail": "FAIL"}


def main():
    print("Pre-flight check — about 30 seconds.\n")
    results = []

    for name, fn in CHECKS:
        try:
            result = fn()
        except Exception as exc:  # noqa: BLE001 - a broken check must not stop the rest
            result = fail("check itself failed: {}".format(exc))
        results.append((name, result))
        print("[{}] {:<18} {}".format(MARK[result.status], name, result.detail))
        if result.fix:
            for line in _wrap(result.fix, 66):
                print("       {}".format(line))

    failures = [n for n, r in results if r.status == "fail"]
    warnings = [n for n, r in results if r.status == "warn"]

    print()
    if failures:
        print("NOT READY — {} check(s) failed: {}".format(
            len(failures), ", ".join(failures)))
        print("Fix those first; a session now would record nothing usable.")
        return 1
    if warnings:
        print("READY, with {} thing(s) to be aware of: {}".format(
            len(warnings), ", ".join(warnings)))
        return 0
    print("READY. Everything checks out.")
    return 0


def _wrap(text, width):
    words, line, out = text.split(), "", []
    for word in words:
        if len(line) + len(word) + 1 > width:
            out.append(line)
            line = word
        else:
            line = "{} {}".format(line, word).strip()
    if line:
        out.append(line)
    return out


if __name__ == "__main__":
    sys.exit(main())
