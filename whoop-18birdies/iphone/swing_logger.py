"""Golf swing detector and logger for iPhone, using Pythonista's motion sensors.

Approximates what the 18Birdies watchOS app does on an Apple Watch: watch the
accelerometer for the spike a golf swing produces, tag each detection with GPS,
and derive what mechanics a single arm-worn sensor can honestly give — tempo
above all, reported both as a ratio and in Tour Tempo's 30fps frame units so it
reads directly against the published 21/7, 24/8, 27/9 elite groups.

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
In a pocket the swing is only ~3x your walking motion and detection gets
marginal; on the forearm it is ~8x and easy.

iOS only delivers motion updates to a FOREGROUND app, so this script must stay
on screen for the whole session. Set Settings -> Display -> Auto-Lock to Never
and start on a full battery.

USAGE
-----
Tap run and pick a mode. Detection self-calibrates from your own motion, so no
manual threshold is needed. The log autosaves after every swing — killing the
app loses at most the swing in flight, not the session.
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
    tour_tempo_frames,
)

# --- Tuning ------------------------------------------------------------------

# Detection calibrates itself by default: it tracks a rolling median of your
# own motion and fires on a multiple of it, adapting to wherever the phone
# actually is. Set AUTO_THRESHOLD = False to pin a fixed number in g instead.
AUTO_THRESHOLD = True
SWING_THRESHOLD_G = 6.0

# Ignore anything this soon after a detection. A swing is one event but spans
# many samples, and the follow-through would otherwise register again.
REFRACTORY_SECONDS = 3.0

# Target sample rate. The loop paces itself against the clock rather than
# sleeping a fixed interval, so work time does not silently erode the rate;
# the log records what was actually achieved.
TARGET_HZ = 100

# How much history to keep for mechanics. Must comfortably exceed a full
# backswing plus downswing (tour swings run ~1.0-1.2 s in total).
BUFFER_SECONDS = 2.5

# The threshold trips on the RISING edge, before impact. Keep sampling this
# long afterwards so the true peak — and the follow-through — are in the window
# before it is analysed.
POST_PEAK_SECONDS = 0.4

# Print a rolling mini-summary every N swings, so a session gives feedback
# while it runs instead of only at the end.
LIVE_STATS_EVERY = 10

# Play a short sound on each detection, so you know it registered without
# looking at your arm. Best-effort: if the sound module misbehaves it is
# dropped silently rather than taking the session down.
SOUND_CUE = True

# Read live heart rate from a WHOOP strap over Bluetooth. Needs HR Broadcast
# enabled once in the WHOOP app (Menu -> Device Settings -> HR Broadcast). If
# no strap is found within the scan timeout, the session runs without it.
WHOOP_HR = True

# Optional: POST each round to `wb serve`. Leave URL empty to log locally.
INGEST_URL = ""      # e.g. "http://192.168.1.24:8790/rounds"
INGEST_TOKEN = ""

LOG_PATH = os.path.expanduser("~/Documents/swings.json")
RANGE_LOG_PATH = os.path.expanduser("~/Documents/range_session.json")


# --- Sensor helpers ----------------------------------------------------------


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


def play_cue():
    if not SOUND_CUE:
        return
    try:
        import sound

        sound.play_effect("arcade:Coin_2")
    except Exception:
        pass  # a missing sound must never cost a swing


class PacedLoop:
    """Keeps a polling loop at a target rate by pacing against the clock.

    A bare sleep(1/hz) ignores how long the loop body took, so the achieved
    rate quietly lands well under target. This schedules each tick absolutely
    and, when the loop falls behind, resets rather than spiralling into a
    backlog of overdue ticks.
    """

    def __init__(self, hz):
        self.interval = 1.0 / hz
        self.next_tick = time.monotonic()

    def wait(self):
        self.next_tick += self.interval
        delay = self.next_tick - time.monotonic()
        if delay > 0:
            time.sleep(delay)
        else:
            self.next_tick = time.monotonic()


# --- Calibration (optional; detection no longer requires it) ------------------


def calibrate(seconds=30):
    """Prints peak magnitudes per second — useful for judging placement."""
    motion.start_updates()
    print("Calibrating. Walk around, then take a few full swings.\n")
    try:
        deadline = time.time() + seconds
        peak = window_peak = 0.0
        next_report = time.time() + 1.0
        samples = 0
        pacer = PacedLoop(TARGET_HZ)

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
            pacer.wait()
    finally:
        motion.stop_updates()

    print("\nOverall peak: {:.2f} g over {} samples".format(peak, samples))
    print("Sample rate achieved: {:.0f} Hz".format(samples / seconds))
    print(
        "\nDetection self-calibrates, so no number to set. These peaks tell you\n"
        "about PLACEMENT: swing peaks 5x+ your walking peaks is a good spot."
    )


# --- The session loop (shared by range and round) ------------------------------


def resolve_swing(buffer, trip_time, index, use_gps):
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
    swing = {
        "index": index,
        "timestamp": time.strftime(
            "%Y-%m-%dT%H:%M:%S", time.localtime(samples[peak_index][0])
        ),
    }
    if use_gps:
        swing["location"] = read_location()
    swing.update(analyse_swing(samples, peak_index))
    swing["tempo_frames"] = tour_tempo_frames(
        swing.get("backswing_s"), swing.get("downswing_s")
    )
    return swing


def autosave(path, mode, swings, detector, started, samples):
    """Writes the log now. Called after every swing: a crash mid-session then
    costs at most the swing in flight, never the session."""
    elapsed = max(1e-6, time.time() - started)
    with open(path, "w") as handle:
        json.dump(
            {
                "mode": mode,
                "auto_threshold": AUTO_THRESHOLD,
                "threshold_g": (
                    round(detector.threshold(), 2) if detector else SWING_THRESHOLD_G
                ),
                "sample_rate_hz": round(samples / elapsed),
                "swings": swings,
            },
            handle,
            indent=2,
        )


def live_stats(swings):
    tempo = consistency(swings, "tempo_ratio")
    if tempo:
        print(
            "  -- {} swings; tempo {:.2f}:1, spread {:.2f} --".format(
                len(swings), tempo["mean"], tempo["stdev"]
            )
        )
    else:
        print("  -- {} swings; no tempo readings yet --".format(len(swings)))


def run_session(mode):
    """The detection loop. mode is 'round' (GPS + distances) or 'range'."""
    use_gps = mode == "round"
    log_path = LOG_PATH if use_gps else RANGE_LOG_PATH

    swings = []
    buffer = deque(maxlen=max(16, int(BUFFER_SECONDS * TARGET_HZ)))
    detector = AdaptiveThreshold(sample_hz=TARGET_HZ) if AUTO_THRESHOLD else None

    hr = None
    if WHOOP_HR:
        try:
            from hr_monitor import HeartRateMonitor

            print("Scanning for a broadcasting WHOOP (12s)...")
            candidate = HeartRateMonitor()
            if candidate.start(timeout=12):
                hr = candidate
                print("WHOOP connected — live heart rate on every swing.")
            else:
                print(
                    "No WHOOP found. Check HR Broadcast is ON in the WHOOP app\n"
                    "(Menu -> Device Settings). Continuing without heart rate."
                )
        except Exception as exc:
            print("Heart rate unavailable ({}). Continuing without it.".format(exc))

    motion.start_updates()
    if use_gps:
        location.start_updates()
    else:
        print("Range mode: no GPS — distance is meaningless standing still.")
        print("Practice swings count as swings; keep them clear of real ones.")

    print(
        "Watching for swings. Threshold: {}.".format(
            "self-calibrating" if detector else "fixed {:.1f} g".format(SWING_THRESHOLD_G)
        )
    )
    print("Keep this screen on. Stop the script to finish (log autosaves).\n")

    started = time.time()
    samples = 0
    pacer = PacedLoop(TARGET_HZ)

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
                swing = resolve_swing(buffer, trip_time, len(swings) + 1, use_gps)
                if swing:
                    if hr:
                        swing["hr_bpm"] = hr.current_bpm()
                    swings.append(swing)
                    play_cue()
                    tempo = swing.get("tempo_ratio")
                    frames = swing.get("tempo_frames")
                    loc = swing.get("location")
                    where = ""
                    if use_gps:
                        where = (
                            "  {:.5f}, {:.5f}".format(loc["latitude"], loc["longitude"])
                            if loc and loc.get("latitude") is not None
                            else "  no GPS fix"
                        )
                    bpm = swing.get("hr_bpm")
                    print(
                        "swing {:>3}  {:5.1f} g  tempo {}{}{}{}".format(
                            swing["index"],
                            swing["peak_g"],
                            "{:.1f}:1".format(tempo) if tempo else "-",
                            " ({})".format(frames) if frames else "",
                            "  {} bpm".format(bpm) if bpm else "",
                            where,
                        )
                    )
                    autosave(log_path, mode, swings, detector, started, samples)
                    if len(swings) % LIVE_STATS_EVERY == 0:
                        live_stats(swings)
                last_detection = now
                trip_time = None

            pacer.wait()

    except KeyboardInterrupt:
        pass
    finally:
        motion.stop_updates()
        if use_gps:
            location.stop_updates()
        live_hrv = hr.live_hrv_ms() if hr else None
        if hr:
            hr.stop()

        elapsed = max(1e-6, time.time() - started)
        fit = None
        if use_gps:
            # Distance is measured, not modelled: you walk to your ball, so the
            # line from one swing to the next is how far the ball went.
            shot_distances(swings)
            fit = fit_swings(swings)

        autosave(log_path, mode, swings, detector, started, samples)
        if use_gps:
            print_round_summary(swings, elapsed, samples, fit)
        else:
            print_range_summary(swings, elapsed, samples)
        print_hr_block(swings, live_hrv)
        print("\nSaved to {}".format(log_path))
        if use_gps:
            post_round(swings)


# --- Summaries -----------------------------------------------------------------


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

    _print_tempo_block(swings)

    for label, key in (("distance", "distance_yd"), ("tempo", "tempo_ratio")):
        drift = fatigue_split(swings, key)
        if not drift:
            continue
        direction = "down" if drift["change"] < 0 else "up"
        print(
            "\nBack-half {}: {} {:.1f}% ({:.2f} -> {:.2f})".format(
                label, direction, abs(drift["change_pct"]),
                drift["early_mean"], drift["late_mean"],
            )
        )

    if fit:
        print(
            "\nSwing-to-distance fit: {:.1f} yd per g, r2={:.2f} over {} shots.".format(
                fit["slope"], fit["r2"], fit["n"]
            )
        )
        if fit["r2"] < 0.3:
            print("  Weak fit — more shots and a consistent phone position will help.")
    else:
        print("\nNot enough measured shots yet to fit swing strength to distance.")


def print_range_summary(swings, elapsed, samples):
    print(
        "\n{} swing(s) over {:.0f} min at ~{:.0f} Hz.".format(
            len(swings), elapsed / 60, samples / elapsed
        )
    )
    if not swings:
        print(
            "Nothing detected. If the screen stayed on and the phone was on your\n"
            "arm, run Calibrate and send the numbers — that should not happen."
        )
        return

    with_tempo = [s for s in swings if s.get("tempo_ratio") is not None]
    print("Tempo derived on {} of {} swings.".format(len(with_tempo), len(swings)))
    if len(with_tempo) < len(swings) / 2:
        print(
            "  Over half missing — the phase finder needs a still moment at address.\n"
            "  Pause a beat before each swing rather than raking ball to ball."
        )

    _print_tempo_block(swings)

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


def _print_tempo_block(swings):
    tempo = consistency(swings, "tempo_ratio")
    if not tempo:
        print("\nNo tempo readings — phases need a quiet-then-swing window.")
        return

    back = consistency(swings, "backswing_s")
    down = consistency(swings, "downswing_s")
    frames = ""
    if back and down:
        frames = "   (Tour Tempo {} — elite groups are 21/7, 24/8, 27/9)".format(
            tour_tempo_frames(back["mean"], down["mean"])
        )

    print(
        "\nTempo   {:.2f}:1   stdev {:.2f}   cv {:.3f}   ({} swings){}".format(
            tempo["mean"], tempo["stdev"], tempo["cv"], tempo["n"], frames
        )
    )
    print("  {}".format(tempo_verdict(tempo["mean"])))
    if tempo["cv"] < 0.06:
        print("  Very repeatable — that is a well-grooved tempo.")
    elif tempo["cv"] < 0.12:
        print("  Reasonably repeatable.")
    else:
        print("  Scattered — tempo is varying a lot swing to swing.")


def print_hr_block(swings, live_hrv):
    """Heart-rate read-out for the session, if a WHOOP was streaming."""
    stats = consistency(swings, "hr_bpm")
    if not stats:
        return
    print(
        "\nHeart rate (WHOOP, live): {:.0f} bpm avg over {} swings".format(
            stats["mean"], stats["n"]
        )
    )
    drift = fatigue_split(swings, "hr_bpm")
    if drift:
        direction = "up" if drift["change"] > 0 else "down"
        print(
            "  second half: {} {:.1f}% ({:.0f} -> {:.0f} bpm)".format(
                direction, abs(drift["change_pct"]),
                drift["early_mean"], drift["late_mean"],
            )
        )
        if drift["change_pct"] > 5:
            print("  Rising HR at the same workload is the cardio face of fatigue —")
            print("  worth reading against tempo and distance drift above.")
    if live_hrv is not None:
        print("  live HRV (rMSSD from broadcast RR): {:.0f} ms".format(live_hrv))
        print("  (session estimate; not WHOOP's overnight HRV score)")


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


# --- Entry ---------------------------------------------------------------------


def choose_mode():
    """Mode picker. Pythonista's run button passes no argv, so ask on screen."""
    import sys

    if len(sys.argv) > 1:
        return sys.argv[1]

    choice = console.alert(
        "Swing Logger",
        "Detection self-calibrates. Calibrate mode just reports placement quality.",
        "Range (no GPS)",
        "Play a round",
        "Calibrate (30s)",
        hide_cancel_button=False,
    )
    return {1: "range", 2: "detect"}.get(choice, "calibrate")


if __name__ == "__main__":
    try:
        mode = choose_mode()
    except KeyboardInterrupt:  # console.alert raises this on cancel
        raise SystemExit(0)

    if mode == "calibrate":
        calibrate()
    elif mode == "range":
        run_session("range")
    else:
        run_session("round")
