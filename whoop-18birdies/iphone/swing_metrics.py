"""Swing mechanics extracted from a captured motion window.

The detector only needs a peak to know a swing happened. The window around
that peak carries much more, and this pulls it out.

The headline metric is TEMPO — the ratio of backswing time to downswing time.
It is a real coaching number (tour players cluster near 3:1) and, unlike swing
path or face angle, it is genuinely derivable from a single arm-worn sensor,
because it depends only on WHEN the phases happen, not on where the club is in
space.

A caveat worth knowing rather than discovering: the measured ratio runs about
5% low. Motion start is taken as the end of the last sustained quiet stretch,
which lands just inside the takeaway rather than exactly at it, clipping a
fraction of the backswing. The bias is systematic, so comparing your tempo
against your own history is sound; comparing the absolute number against a
published 3:1 benchmark is slightly unfair to you.

Pure Python, no Pythonista imports, so it is testable off-device.
"""

import math

# Motion below this (in g of user acceleration) counts as standing still.
QUIET_G = 0.35

# A swing's phases live within this much time before the impact peak. Longer
# windows start swallowing the previous shot's follow-through or a practice
# swing.
MAX_BACKSWING_S = 2.0


def _mean(xs):
    return sum(xs) / len(xs) if xs else float("nan")


def _stdev(xs):
    if len(xs) < 2:
        return float("nan")
    m = _mean(xs)
    return math.sqrt(sum((x - m) ** 2 for x in xs) / (len(xs) - 1))


# The arm goes briefly quiet at the top of the backswing, so a single quiet
# sample cannot mean the swing has not started. Only a sustained stretch of
# stillness marks the address position before the takeaway.
QUIET_RUN_S = 0.15


def find_motion_start(samples, peak_index):
    """First sample of the backswing, walking back from impact.

    Returns the point after the last sustained stretch of stillness. The run
    requirement matters: at the top of the backswing the club momentarily stops
    and acceleration dips below the quiet threshold, so a naive "first quiet
    sample" search would mistake the transition for the start of the swing and
    throw the backswing away entirely.
    """
    if peak_index <= 0:
        return None

    t_peak = samples[peak_index][0]
    quiet_run = 0
    i = peak_index

    while i > 0:
        i -= 1
        t, mag = samples[i][0], samples[i][1]
        if t_peak - t > MAX_BACKSWING_S:
            return i + 1

        if mag < QUIET_G:
            quiet_run += 1
            # Measure the run in time, so this holds at any sample rate.
            run_start_t = samples[i + quiet_run - 1][0]
            if run_start_t - t >= QUIET_RUN_S:
                return i + quiet_run
        else:
            quiet_run = 0

    return 0


def find_transition(samples, peak_index, start_index=None):
    """Index of the top of the backswing: the quietest moment during the swing.

    At the top the club momentarily stops, so linear acceleration dips to a
    local minimum between the backswing ramp and the downswing spike. The
    search is bounded below by the start of motion — searching a fixed lookback
    instead would find the stillness before the swing, which is quieter still.
    """
    if peak_index <= 0:
        return None

    if start_index is None:
        start_index = find_motion_start(samples, peak_index)
    if start_index is None or start_index >= peak_index:
        return None

    window = samples[start_index:peak_index]
    if len(window) < 3:
        return None

    quietest = min(range(len(window)), key=lambda i: window[i][1])
    return start_index + quietest


def attitude_sweep(samples, start_index, end_index):
    """Peak-to-peak roll/pitch/yaw travel over a span, in degrees.

    A proxy for how far the body and arms rotated. Not swing plane — that needs
    the club's position in space, which one sensor on your arm cannot give.
    """
    rolls, pitches, yaws = [], [], []
    for sample in samples[start_index : end_index + 1]:
        attitude = sample[2] if len(sample) > 2 else None
        if not attitude:
            continue
        r, p, y = attitude
        rolls.append(r)
        pitches.append(p)
        yaws.append(y)

    if not rolls:
        return None

    def span(values):
        return round(math.degrees(max(values) - min(values)), 1)

    return {"roll_deg": span(rolls), "pitch_deg": span(pitches), "yaw_deg": span(yaws)}


def analyse_swing(samples, peak_index=None):
    """Derives mechanics from a motion window.

    `samples` is [(t_seconds, accel_magnitude_g, attitude_or_None), ...] in time
    order. Returns whatever could be derived; fields that need phases the window
    does not contain come back None rather than guessed.
    """
    if not samples:
        return {}

    if peak_index is None:
        peak_index = max(range(len(samples)), key=lambda i: samples[i][1])

    result = {
        "peak_g": round(samples[peak_index][1], 2),
        "backswing_s": None,
        "downswing_s": None,
        "tempo_ratio": None,
        "attitude_sweep": None,
    }

    start = find_motion_start(samples, peak_index)
    if start is None:
        return result

    transition = find_transition(samples, peak_index, start)
    if transition is None:
        return result

    t_start = samples[start][0]
    t_transition = samples[transition][0]
    t_peak = samples[peak_index][0]

    backswing = t_transition - t_start
    downswing = t_peak - t_transition

    result["backswing_s"] = round(backswing, 3)
    result["downswing_s"] = round(downswing, 3)
    if downswing > 0.01 and backswing > 0.01:
        result["tempo_ratio"] = round(backswing / downswing, 2)
    result["attitude_sweep"] = attitude_sweep(samples, start, peak_index)

    return result


# --- Across a round ----------------------------------------------------------

# Tour players cluster tightly around 3:1 backswing-to-downswing.
TOUR_TEMPO = 3.0


def tempo_verdict(ratio):
    if ratio is None or not math.isfinite(ratio):
        return "no reading"
    if ratio < TOUR_TEMPO - 0.6:
        return "quick backswing — rushing the takeaway"
    if ratio > TOUR_TEMPO + 0.6:
        return "slow backswing relative to your downswing"
    return "near the 3:1 tour benchmark"


def consistency(swings, key):
    """Mean and spread of a metric across swings. Lower spread is better."""
    values = [
        s[key] for s in swings if s.get(key) is not None and math.isfinite(s[key])
    ]
    if len(values) < 2:
        return None
    m = _mean(values)
    sd = _stdev(values)
    return {
        "mean": round(m, 2),
        "stdev": round(sd, 2),
        # Coefficient of variation makes spread comparable across metrics with
        # different units and scales.
        "cv": round(sd / m, 3) if m else None,
        "n": len(values),
    }


def fatigue_split(swings, key):
    """Compares the metric's first half of the round against its second.

    This is where a wearable earns its keep on a golf course: whether you are
    losing distance or tempo as the round wears on, and by how much.
    """
    values = [
        s[key] for s in swings if s.get(key) is not None and math.isfinite(s[key])
    ]
    if len(values) < 6:
        return None

    half = len(values) // 2
    early, late = values[:half], values[half:]
    early_mean, late_mean = _mean(early), _mean(late)
    if not early_mean:
        return None

    return {
        "early_mean": round(early_mean, 2),
        "late_mean": round(late_mean, 2),
        "change": round(late_mean - early_mean, 2),
        "change_pct": round((late_mean - early_mean) / early_mean * 100, 1),
        "n_early": len(early),
        "n_late": len(late),
    }
