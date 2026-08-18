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

    Returns the point after the last sustained stretch of stillness, or None
    when no such address pause exists in the window. The run requirement
    matters: at the top of the backswing the club momentarily stops and
    acceleration dips below the quiet threshold, so a naive "first quiet sample"
    search would mistake the transition for the start of the swing and throw the
    backswing away entirely.

    Returning None when there is no resolvable address is the load-bearing part:
    a swing taken straight out of walking has no quiet lead-in, and fabricating
    a start inside that motion produces a nonsense tempo (a 0.06 s backswing
    against a 1.9 s downswing) that then poisons the round's tempo stats without
    tripping the missing-data warning. Honest None keeps it out.
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
            # Reached the lookback bound with no sustained quiet stretch: no
            # address to anchor to, so report none rather than guess.
            return None

        if mag < QUIET_G:
            quiet_run += 1
            # Measure the run in time, so this holds at any sample rate.
            run_start_t = samples[i + quiet_run - 1][0]
            if run_start_t - t >= QUIET_RUN_S:
                return i + quiet_run
        else:
            quiet_run = 0

    # Ran out of window before any sustained quiet stretch — same story.
    return None


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


def _unwrap(values):
    """Undo the +/-pi wrap in an angle sequence, in place of the raw values.

    Core Motion reports roll and yaw in (-pi, pi], so a body turn that crosses
    pi jumps straight to -pi. Taking max-min across the raw values then reads
    that 0.02 rad step as 6.26 rad: a measured 45-degree shoulder turn comes
    back as 359 degrees, which looks like a complete rotation rather than an
    obvious error. Which holes it strikes depends only on the compass direction
    you happen to be aimed at, so it appears and disappears for no visible
    reason.

    Standard phase unwrapping: whenever consecutive samples differ by more than
    pi, the smaller interpretation is the true one, so shift by 2pi.
    """
    if not values:
        return []
    out = [values[0]]
    offset = 0.0
    for previous, current in zip(values, values[1:]):
        delta = current - previous
        if delta > math.pi:
            offset -= 2 * math.pi
        elif delta < -math.pi:
            offset += 2 * math.pi
        out.append(current + offset)
    return out


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
        unwrapped = _unwrap(values)
        return round(math.degrees(max(unwrapped) - min(unwrapped)), 1)

    # Pitch is reported in [-pi/2, pi/2] and does not wrap, so unwrapping it is
    # a no-op; running it anyway keeps the three axes handled identically.
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


# --- Adaptive detection ------------------------------------------------------


class AdaptiveThreshold:
    """A swing threshold that calibrates itself from your own recent motion.

    A fixed threshold in g assumes you know where the phone is: on a lead
    forearm a swing spikes past 10 g, in a pocket it may never clear 4. Pick
    wrong and you get either nothing or constant false positives.

    A swing is enormous relative to whatever else that phone is doing, though,
    whatever the placement — so this tracks a rolling baseline of ordinary
    motion and fires on a large multiple of it. The baseline is a median rather
    than a mean, because the swing spikes are themselves in the window and would
    drag a mean upward until the detector stopped firing.

    The default ratio of 2.0 was tuned against simulated gait. It catches swings
    from arm amplitude (12 g) down to a gentle chip (2 g) with no false
    positives, while 2.5 and above lose everything below arm amplitude entirely.

    The margin is not uniform, and that is worth knowing. On a lead forearm a
    swing is roughly 8x the walking median, an enormous gap. In a pocket it is
    nearer 3x while gait peaks already reach 2x, so the discrimination there is
    genuinely marginal — a property of the placement, not of the threshold.
    """

    def __init__(
        self,
        window_seconds=10.0,
        ratio=2.0,
        floor_g=1.5,
        sample_hz=100,
        recompute_every=25,
    ):
        self.ratio = ratio
        self.floor_g = floor_g
        self.window = []
        self.max_samples = max(32, int(window_seconds * sample_hz))
        # The median is recomputed periodically rather than per sample. Sorting
        # a thousand-sample window on every observation is O(n log n) at 100 Hz
        # and measurably eats the phone's sample rate; the baseline drifts on a
        # scale of seconds, so a quarter-second-stale median costs nothing.
        self.recompute_every = max(1, recompute_every)
        self._cached_median = None
        self._since_recompute = 0

    def observe(self, magnitude):
        self.window.append(magnitude)
        if len(self.window) > self.max_samples:
            # Drop a chunk at a time; pop(0) on a list is O(n) per sample.
            del self.window[: len(self.window) - self.max_samples]

        self._since_recompute += 1
        if self._cached_median is None or self._since_recompute >= self.recompute_every:
            self._cached_median = self._compute_median()
            self._since_recompute = 0

    def _compute_median(self):
        if not self.window:
            return None
        ordered = sorted(self.window)
        mid = len(ordered) // 2
        if len(ordered) % 2:
            return ordered[mid]
        return (ordered[mid - 1] + ordered[mid]) / 2

    def baseline(self):
        if self._cached_median is None:
            self._cached_median = self._compute_median()
        return self._cached_median

    def ready(self):
        """True once there is enough history for the baseline to mean anything."""
        return len(self.window) >= self.max_samples // 4

    def threshold(self):
        base = self.baseline()
        if base is None:
            return self.floor_g
        # The floor stops perfect stillness from making everything a swing.
        return max(self.floor_g, base * self.ratio)

    def is_swing(self, magnitude):
        return self.ready() and magnitude >= self.threshold()


# --- Across a round ----------------------------------------------------------

# Tour players cluster tightly around 3:1 backswing-to-downswing. Source:
# John Novosel's Tour Tempo frame-count study of tour swings, independently
# corroborated by a later Yale paper. Elite examples run ~0.7-0.9 s back and
# ~0.23-0.3 s down regardless of overall speed.
TOUR_TEMPO = 3.0

# Tour Tempo expresses a swing in 30 fps video frames — the elite groups are
# 21/7, 24/8 and 27/9. Reporting the same units makes a swing directly
# comparable against those published numbers.
TOUR_TEMPO_FPS = 30.0


def tour_tempo_frames(backswing_s, downswing_s):
    """A swing's phases in Tour Tempo's 30fps frame units, e.g. '24/8'."""
    if backswing_s is None or downswing_s is None:
        return None
    return "{:.0f}/{:.0f}".format(
        backswing_s * TOUR_TEMPO_FPS, downswing_s * TOUR_TEMPO_FPS
    )


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
