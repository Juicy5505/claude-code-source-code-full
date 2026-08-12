"""Golf swing detector for iPhone, using Pythonista's motion sensors.

Approximates what the 18Birdies watchOS app does on an Apple Watch: watch the
accelerometer for the sharp spike a golf swing produces, and tag each detection
with a GPS location.

WHAT THIS IS NOT
----------------
* It cannot write shots into 18Birdies. 18Birdies has no public API, so this
  produces a standalone log you correlate afterwards.
* It measures that a swing HAPPENED and where you stood. It does not measure
  swing path, face angle, or club head speed — a wrist-worn phone cannot.

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
Tap the run button in Pythonista and pick a mode when prompted. Pythonista runs
scripts with no command-line arguments, so the mode is chosen from a dialog
rather than argv — though argv still works if you invoke it from a shell:

    python swing_logger.py calibrate

Tune SWING_THRESHOLD_G from the calibrate output before trusting a round.
"""

import json
import os
import time

import console
import location
import motion

# --- Tuning ------------------------------------------------------------------

# Peak user-acceleration magnitude, in g, that counts as a swing. A full swing
# on the lead forearm spikes well above everyday motion, but the right number
# depends on your tempo and exactly where the phone is strapped. Run
# `calibrate` and pick something comfortably above your walking peaks.
SWING_THRESHOLD_G = 6.0

# Ignore anything this soon after a detection. A swing is one event but spans
# many samples, and the follow-through would otherwise register again.
REFRACTORY_SECONDS = 3.0

# Target sample rate. Pythonista polls rather than streams, so this is a
# ceiling — the log records the rate actually achieved.
TARGET_HZ = 100

# Optional: POST each detection to `wb serve`. Leave URL empty to log locally.
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


def detect():
    swings = []
    motion.start_updates()
    location.start_updates()

    print("Watching for swings. Threshold {:.1f} g.".format(SWING_THRESHOLD_G))
    print("Keep this screen on and in front. Ctrl-C / stop to finish.\n")

    try:
        last_detection = 0.0
        samples = 0
        started = time.time()

        while True:
            mag = magnitude(motion.get_user_acceleration())
            samples += 1
            now = time.time()

            if mag >= SWING_THRESHOLD_G and (now - last_detection) >= REFRACTORY_SECONDS:
                last_detection = now
                swing = {
                    "index": len(swings) + 1,
                    "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(now)),
                    "peak_g": round(mag, 2),
                    "location": read_location(),
                }
                swings.append(swing)

                loc = swing["location"]
                where = (
                    "{:.5f}, {:.5f}".format(loc["latitude"], loc["longitude"])
                    if loc and loc.get("latitude") is not None
                    else "no GPS fix"
                )
                print(
                    "swing {:>3}  {:.1f} g  {}".format(swing["index"], mag, where)
                )

            time.sleep(1.0 / TARGET_HZ)

    except KeyboardInterrupt:
        pass
    finally:
        motion.stop_updates()
        location.stop_updates()

        elapsed = max(1e-6, time.time() - started)
        with open(LOG_PATH, "w") as handle:
            json.dump(
                {
                    "threshold_g": SWING_THRESHOLD_G,
                    "sample_rate_hz": round(samples / elapsed),
                    "swings": swings,
                },
                handle,
                indent=2,
            )

        print(
            "\n{} swing(s) detected over {:.0f} min at ~{:.0f} Hz.".format(
                len(swings), elapsed / 60, samples / elapsed
            )
        )
        print("Saved to {}".format(LOG_PATH))
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
        "Detect swings",
        hide_cancel_button=False,
    )
    return "calibrate" if choice == 1 else "detect"


if __name__ == "__main__":
    try:
        mode = choose_mode()
    except KeyboardInterrupt:  # console.alert raises this on cancel
        raise SystemExit(0)

    if mode == "calibrate":
        calibrate()
    else:
        detect()
