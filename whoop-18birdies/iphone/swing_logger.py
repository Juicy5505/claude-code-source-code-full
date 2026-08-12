"""Golf swing detector and logger for iPhone, using Pythonista's motion sensors.

Approximates what the 18Birdies watchOS app does on an Apple Watch: watch the
accelerometer for the sharp spike a golf swing produces, tag each detection
with GPS, and derive what mechanics a single arm-worn sensor can honestly give.

WHAT THIS IS NOT
----------------
* It cannot write shots into 18Birdies. 18Birdies has no public API, so this
  produces a standalone log you correlate afterwards.
* It measures WHEN things happened and where you stood. It cannot measure swing
  path, face angle, or club head speed — those need the club's position in
  space, which one sensor on your arm does not give.

PLACEMENT MATTERS MORE THAN THE CODE
------------------------------------
Strap the phone to your LEAD forearm (left arm for a right-handed golfer).
In a pocket the sensor mostly sees hip rotation, which is far too similar to a
practice swing or getting out of a cart to separate reliably.

iOS only delivers motion updates to a FOREGROUND app, so this script must stay
on screen for the whole round. Set Settings -> Display -> Auto-Lock to Never and
start it on a full battery.

USAGE
-----
Tap run in Pythonista and pick a mode. Calibrate before trusting a round.
"""

import json
import os
import time
from collections import deque

import console
import location
import motion

from shot_model import fit_swings, shot_distances
from swing_metrics import (
    AdaptiveThreshold,
    analyse_swing,
    consistency,
    fatigue_split,
    tempo_verdict,
)

# --- Tuning ------------------------------------------------------------------

# Detection calibrates itself by default: it tracks a rolling median of your
# own motion and fires on a multiple of it, so it adapts to wherever the phone
# actually is instead of assuming. Set AUTO_THRESHOLD = False to go back to a
# fixed number in g.
AUTO_THRESHOLD = True
SWING_THRESHOLD_G = 6.0

# Ignore anything this soon after a detection. A swing is one event but spans
# many samples, and the follow-through would otherwise register again.
REFRACTORY_SECONDS = 3.0

# Target sample rate. Pythonista polls rather than streams, so this is a
# ceiling — the log records the rate actually achieved.
TARGET_HZ = 100

# How much history to keep for mechanics. Must comfortably exceed a full
# backswing plus downswing.
BUFFER_SECONDS = 2.5

# The threshold trips on the RISING edge, before impact. Keep sampling this
# long afterwards so the true peak — and the follow-through — are in the window
# before it is analysed.
POST_PEAK_SECONDS = 0.4

# Optional: POST each round to `wb serve`. Leave URL empty to log locally.
INGEST_URL = ""      # e.g. "http://192.168.1.24:8790/rounds"
INGEST_TOKEN = ""

LOG_PATH = os.path.expanduser("~/Documents/swings.json")


def magnitude(vec):
    x, y, z = vec
    return (x * x + y * y + z * z) ** 0.5


def read_location():
    """Best-effort GPS fix. Returns None rather than blocking the detector."""
    try:
        loc = location.get_location()
    except Exception:
        return None
    if not loc:
        return None
    return {
        "latitude": loc.get("latitude"),
        "longitude": loc.get("longitude"),
        "altitude": loc.get("altitude"),
        "horizontal_accuracy": loc.get("horizontal_accuracy"),
    }


def read_attitude():
    try:
        return motion.get_attitude()
    except Exception:
        return None


def calibrate(seconds=30):
    """Prints peak magnitudes so you can pick a threshold that fits you."""
    motion.start_updates()
    print("Calibrating. Walk around, then take a few full swings.\n")
    try:
        deadline = time.time() + seconds
        peak = 0.0
        window_peak = 0.0
        next_report = time.time() + 1.0
        samples = 0

        while time.time() < deadline:
            mag = magnitude(motion.get_user_acceleration())
            samples += 1
            peak = max(peak, mag)
            window_peak = max(window_peak, mag)

            now = time.time()
            if now >= next_report:
                print("  peak this second: {:5.2f} g".format(window_peak))
                window_peak = 0.0
                next_report = now + 1.0

            time.sleep(1.0 / TARGET_HZ)
    finally:
        motion.stop_updates()

    print("\nOverall peak: {:.2f} g over {} samples".format(peak, samples))
    print("Sample rate achieved: {:.0f} Hz".format(samples / seconds))
    print(
        "\nSet SWING_THRESHOLD_G between your walking peaks and your swing peaks —\n"
        "usually around 60-70% of the swing peak."
    )


def post_round(swings):
    """Push the round to `wb serve`, if configured. Never fatal."""
    if not INGEST_URL or not swings:
        return
    try:
        import requests
    except ImportError:
        print("requests unavailable; skipping upload.")
        return

    first, last = swings[0], swings[-1]
    payload = {
        "start": first["timestamp"],
        "end": last["timestamp"],
        "course": "iPhone swing logger",
        "notes": "{} swings detected".format(len(swings)),
    }
    try:
        res = requests.post(
            INGEST_URL,
            json=payload,
            headers={"Authorization": "Bearer " + INGEST_TOKEN},
            timeout=10,
        )
        print("Upload: HTTP {} {}".format(res.status_code, res.text[:200]))
    except Exception as exc:
        print("Upload failed (log is still saved): {}".format(exc))


def resolve_swing(buffer, trip_time, index):
    """Turns a captured window into a swing record.

    The peak is located at or after the threshold trip, not across the whole
    buffer, so a previous shot's follow-through lingering in the window cannot
    be mistaken for this swing's impact.
    """
    samples = list(buffer)
    candidates = [i for i, s in enumerate(samples) if s[0] >= trip_time]
    if not candidates:
        return None

    peak_index = max(candidates, key=lambda i: samples[i][1])
    metrics = analyse_swing(samples, peak_index)

    swing = {
        "index": index,
        "timestamp": time.strftime(
            "%Y-%m-%dT%H:%M:%S", time.localtime(samples[peak_index][0])
        ),
        "location": read_location(),
    }
    swing.update(metrics)
    return swing


def print_round_summary(swings, elapsed, samples, fit):
    print(
        "\n{} swing(s) detected over {:.0f} min at ~{:.0f} Hz.".format(
            len(swings), elapsed / 60, samples / elapsed
        )
    )

    measured = [s for s in swings if s.get("distance_yd") is not None]
    if measured:
        print("\nShot distances (GPS, swing to swing):")
        for swing in measured:
            tempo = swing.get("tempo_ratio")
            tempo_text = "{:4.1f}:1".format(tempo) if tempo else "   -  "
            print(
                "  {:>3}  {:5.1f} g  {}  {:6.1f} yd".format(
                    swing["index"], swing["peak_g"], tempo_text, swing["distance_yd"]
                )
            )
        longest = max(measured, key=lambda s: s["distance_yd"])
        print("  longest: {:.1f} yd".format(longest["distance_yd"]))
    else:
        print("\nNo shot distances — needs GPS fixes on consecutive swings.")

    tempo_stats = consistency(swings, "tempo_ratio")
    if tempo_stats:
        print(
            "\nTempo: {:.2f}:1 average (spread {:.2f} over {} swings)".format(
                tempo_stats["mean"], tempo_stats["stdev"], tempo_stats["n"]
            )
        )
        print("  {}".format(tempo_verdict(tempo_stats["mean"])))
    else:
        print("\nNo tempo readings — the phases need a clean quiet-then-swing window.")

    for label, key in (("distance", "distance_yd"), ("tempo", "tempo_ratio")):
        drift = fatigue_split(swings, key)
        if not drift:
            continue
        direction = "down" if drift["change"] < 0 else "up"
        print(
            "\nBack-half {}: {} {:.1f}% ({:.2f} -> {:.2f} across {} then {} shots)".format(
                label,
                direction,
                abs(drift["change_pct"]),
                drift["early_mean"],
                drift["late_mean"],
                drift["n_early"],
                drift["n_late"],
            )
        )

    if fit:
        print(
            "\nSwing-to-distance fit: {:.1f} yd per g, r2={:.2f} over {} shots.".format(
                fit["slope"], fit["r2"], fit["n"]
            )
        )
        if fit["r2"] < 0.3:
            print(
                "  Weak fit — peak g is not tracking your distance yet.\n"
                "  More shots will help; so will a consistent phone position."
            )
    else:
        print("\nNot enough measured shots yet to fit swing strength to distance.")


RANGE_LOG_PATH = os.path.expanduser("~/Documents/range_session.json")


def range_session():
    """Bucket-of-balls mode: swing quality without distance.

    At a range you never move, so shot-to-shot GPS is nothing but noise. This
    drops location entirely and reports what a stationary session can actually
    measure — tempo, how repeatable it is, and whether it drifts as you tire.
    """
    swings = []
    buffer = deque(maxlen=max(16, int(BUFFER_SECONDS * TARGET_HZ)))
    detector = AdaptiveThreshold(sample_hz=TARGET_HZ) if AUTO_THRESHOLD else None

    motion.start_updates()
    print("Range mode. No GPS — distance is meaningless standing still.")
    print(
        "Threshold: self-calibrating from your own motion."
        if detector
        else "Threshold: fixed at {:.1f} g.".format(SWING_THRESHOLD_G)
    )
    print("Practice swings count as swings; keep them well clear of your real ones.")
    print("Keep this screen on. Stop the script when the bucket is done.\n")

    started = time.time()
    samples = 0

    try:
        last_detection = 0.0
        trip_time = None

        while True:
            now = time.time()
            mag = magnitude(motion.get_user_acceleration())
            buffer.append((now, mag, read_attitude()))
            samples += 1

            if detector:
                detector.observe(mag)

            if trip_time is None:
                tripped = (
                    detector.is_swing(mag) if detector else mag >= SWING_THRESHOLD_G
                )
                if tripped and (now - last_detection) >= REFRACTORY_SECONDS:
                    trip_time = now
            elif now - trip_time >= POST_PEAK_SECONDS:
                swing = resolve_swing_no_gps(buffer, trip_time, len(swings) + 1)
                if swing:
                    swings.append(swing)
                    tempo = swing.get("tempo_ratio")
                    print(
                        "  {:>3}  {:5.1f} g   tempo {}".format(
                            swing["index"],
                            swing["peak_g"],
                            "{:.2f}:1".format(tempo) if tempo else "  -  ",
                        )
                    )
                last_detection = now
                trip_time = None

            time.sleep(1.0 / TARGET_HZ)

    except KeyboardInterrupt:
        pass
    finally:
        motion.stop_updates()
        elapsed = max(1e-6, time.time() - started)

        with open(RANGE_LOG_PATH, "w") as handle:
            json.dump(
                {
                    "mode": "range",
                    "auto_threshold": AUTO_THRESHOLD,
                    "threshold_g": (
                        round(detector.threshold(), 2)
                        if detector
                        else SWING_THRESHOLD_G
                    ),
                    "sample_rate_hz": round(samples / elapsed),
                    "swings": swings,
                },
                handle,
                indent=2,
            )

        print_range_summary(swings, elapsed, samples)
        print("\nSaved to {}".format(RANGE_LOG_PATH))


def resolve_swing_no_gps(buffer, trip_time, index):
    """Same window analysis as a round, minus the location lookup."""
    samples = list(buffer)
    candidates = [i for i, s in enumerate(samples) if s[0] >= trip_time]
    if not candidates:
        return None

    peak_index = max(candidates, key=lambda i: samples[i][1])
    swing = {
        "index": index,
        "timestamp": time.strftime(
            "%Y-%m-%dT%H:%M:%S", time.localtime(samples[peak_index][0])
        ),
    }
    swing.update(analyse_swing(samples, peak_index))
    return swing


def print_range_summary(swings, elapsed, samples):
    print(
        "\n{} swing(s) over {:.0f} min at ~{:.0f} Hz.".format(
            len(swings), elapsed / 60, samples / elapsed
        )
    )
    if not swings:
        print("Nothing detected — lower SWING_THRESHOLD_G and try again.")
        return

    with_tempo = [s for s in swings if s.get("tempo_ratio") is not None]
    print(
        "Tempo derived on {} of {} swings.".format(len(with_tempo), len(swings))
    )
    if len(with_tempo) < len(swings) / 2:
        print(
            "  Over half missing — the phase finder needs a still moment at address.\n"
            "  Pause a beat before each swing rather than raking ball to ball."
        )

    tempo = consistency(swings, "tempo_ratio")
    if tempo:
        print(
            "\nTempo   {:.2f}:1   stdev {:.2f}   cv {:.3f}   ({} swings)".format(
                tempo["mean"], tempo["stdev"], tempo["cv"], tempo["n"]
            )
        )
        print("  {}".format(tempo_verdict(tempo["mean"])))
        # Repeatability is the whole point of a range session.
        if tempo["cv"] < 0.06:
            print("  Very repeatable — that is a well-grooved tempo.")
        elif tempo["cv"] < 0.12:
            print("  Reasonably repeatable.")
        else:
            print("  Scattered — tempo is varying a lot swing to swing.")

    force = consistency(swings, "peak_g")
    if force:
        print(
            "\nPeak g  {:.2f}    stdev {:.2f}   cv {:.3f}".format(
                force["mean"], force["stdev"], force["cv"]
            )
        )

    for label, key in (("tempo", "tempo_ratio"), ("peak g", "peak_g")):
        drift = fatigue_split(swings, key)
        if not drift:
            continue
        direction = "down" if drift["change"] < 0 else "up"
        print(
            "\nSecond half {}: {} {:.1f}%  ({:.2f} -> {:.2f})".format(
                label, direction, abs(drift["change_pct"]),
                drift["early_mean"], drift["late_mean"],
            )
        )


def detect():
    swings = []
    buffer = deque(maxlen=max(16, int(BUFFER_SECONDS * TARGET_HZ)))
    detector = AdaptiveThreshold(sample_hz=TARGET_HZ) if AUTO_THRESHOLD else None

    motion.start_updates()
    location.start_updates()

    print(
        "Watching for swings. Threshold: {}".format(
            "self-calibrating" if detector else "{:.1f} g".format(SWING_THRESHOLD_G)
        )
    )
    print("Keep this screen on and in front. Stop the script to finish.\n")

    started = time.time()
    samples = 0

    try:
        last_detection = 0.0
        trip_time = None

        while True:
            now = time.time()
            mag = magnitude(motion.get_user_acceleration())
            buffer.append((now, mag, read_attitude()))
            samples += 1

            if detector:
                detector.observe(mag)

            if trip_time is None:
                tripped = (
                    detector.is_swing(mag) if detector else mag >= SWING_THRESHOLD_G
                )
                if tripped and (now - last_detection) >= REFRACTORY_SECONDS:
                    trip_time = now
            elif now - trip_time >= POST_PEAK_SECONDS:
                swing = resolve_swing(buffer, trip_time, len(swings) + 1)
                if swing:
                    swings.append(swing)
                    loc = swing.get("location")
                    where = (
                        "{:.5f}, {:.5f}".format(loc["latitude"], loc["longitude"])
                        if loc and loc.get("latitude") is not None
                        else "no GPS fix"
                    )
                    tempo = swing.get("tempo_ratio")
                    print(
                        "swing {:>3}  {:5.1f} g  tempo {}  {}".format(
                            swing["index"],
                            swing["peak_g"],
                            "{:.1f}:1".format(tempo) if tempo else "-",
                            where,
                        )
                    )
                last_detection = now
                trip_time = None

            time.sleep(1.0 / TARGET_HZ)

    except KeyboardInterrupt:
        pass
    finally:
        motion.stop_updates()
        location.stop_updates()

        elapsed = max(1e-6, time.time() - started)

        # Distance is measured, not modelled: you walk to your ball, so the
        # straight line from one swing to the next is how far the ball went.
        shot_distances(swings)
        fit = fit_swings(swings)

        with open(LOG_PATH, "w") as handle:
            json.dump(
                {
                    "auto_threshold": AUTO_THRESHOLD,
                    "threshold_g": (
                        round(detector.threshold(), 2)
                        if detector
                        else SWING_THRESHOLD_G
                    ),
                    "sample_rate_hz": round(samples / elapsed),
                    "fit": fit,
                    "swings": swings,
                },
                handle,
                indent=2,
            )

        print_round_summary(swings, elapsed, samples, fit)
        print("\nSaved to {}".format(LOG_PATH))
        post_round(swings)


def choose_mode():
    """Mode picker. Pythonista's run button passes no argv, so ask on screen."""
    import sys

    if len(sys.argv) > 1:
        return sys.argv[1]

    choice = console.alert(
        "Swing Logger",
        "Calibrate first if you have not tuned the threshold for this phone position.",
        "Calibrate (30s)",
        "Range (no GPS)",
        "Play a round",
        hide_cancel_button=False,
    )
    return {1: "calibrate", 2: "range"}.get(choice, "detect")


if __name__ == "__main__":
    try:
        mode = choose_mode()
    except KeyboardInterrupt:  # console.alert raises this on cancel
        raise SystemExit(0)

    if mode == "calibrate":
        calibrate()
    elif mode == "range":
        range_session()
    else:
        detect()
