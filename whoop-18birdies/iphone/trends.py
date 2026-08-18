"""Track how your game moves across many logged sessions.

One session is an anecdote; the point of logging is the trend. This reads a
series of session logs (range_session.json / swings.json files, oldest to
newest) and reports the direction of each metric — tempo, tempo consistency,
distance, heart rate — with a plain-language verdict that knows which way is
"better" for each.

Pure Python, no device imports, fully testable off-device.
"""

from swing_metrics import consistency

# For each metric: how to reduce a session to one number, and which direction
# counts as improvement. "target" means closeness to a value is better.
METRICS = {
    "tempo_ratio": {"label": "tempo", "agg": "mean", "better": "target", "target": 3.0, "unit": ":1"},
    "tempo_consistency": {"label": "tempo consistency", "agg": "cv", "key": "tempo_ratio", "better": "lower", "unit": " cv"},
    "distance_yd": {"label": "distance", "agg": "mean", "better": "higher", "unit": " yd"},
    "peak_g": {"label": "swing force", "agg": "mean", "better": "higher", "unit": " g"},
    "hr_bpm": {"label": "heart rate", "agg": "mean", "better": "lower", "unit": " bpm"},
}


def _mean(xs):
    return sum(xs) / len(xs) if xs else float("nan")


def linear_slope(values, xs=None):
    """Least-squares slope of values against `xs`, defaulting to 0,1,2,...

    `xs` matters when sessions are missing the metric. Compacting the values and
    regressing against their new positions silently rescales the slope: a metric
    present in sessions 1 and 3 but not 2 is fitted over a run of one instead of
    two, so "per session" means something different for every metric in the same
    report. The direction is unaffected — compaction preserves order — but the
    magnitude is not, and it is a documented field.
    """
    n = len(values)
    if n < 2:
        return None
    xs = list(range(n)) if xs is None else list(xs)
    if len(xs) != n:
        return None
    mx = _mean(xs)
    my = _mean(values)
    sxx = sum((x - mx) ** 2 for x in xs)
    if sxx == 0:
        return None
    sxy = sum((x - mx) * (v - my) for x, v in zip(xs, values))
    return sxy / sxx


def session_value(swings, spec):
    """Reduces one session's swings to a single number for a metric, or None."""
    agg = spec["agg"]
    if agg == "cv":
        stats = consistency(swings, spec["key"])
        return stats["cv"] if stats else None
    key = spec.get("key", None) or _metric_key(spec)
    stats = consistency(swings, key)
    return stats["mean"] if stats else None


def _metric_key(spec):
    # The dict key a spec came from is its data field, except the derived
    # consistency metric which names its source explicitly.
    for name, s in METRICS.items():
        if s is spec:
            return name
    raise KeyError("spec not in METRICS")


def trend_verdict(values, spec):
    """Direction of travel for a metric across sessions.

    Returns {slope, direction, improving} where `improving` is True/False/None
    given the metric's better-is definition, or None if undecidable.
    """
    # Keep each value's SESSION index, so a gap stays a gap on the x-axis.
    points = [(i, v) for i, v in enumerate(values) if v is not None]
    if len(points) < 2:
        return None
    positions = [i for i, _ in points]
    clean = [v for _, v in points]

    raw_slope = linear_slope(clean, positions)

    # A metric that did not move is flat — neither improving nor regressing.
    # Deciding "improving" from the sign of a zero slope would label every
    # unchanged metric as regressing, which is the opposite of true.
    if raw_slope is None or abs(raw_slope) < 1e-9:
        return {"slope": raw_slope or 0.0, "direction": "flat", "improving": None}

    direction = "rising" if raw_slope > 0 else "falling"

    if spec["better"] == "target":
        # Distance from the target is what should shrink.
        target = spec["target"]
        deltas = [abs(v - target) for v in clean]
        dslope = linear_slope(deltas, positions)
        improving = None if dslope is None or abs(dslope) < 1e-9 else dslope < 0
    elif spec["better"] == "higher":
        improving = raw_slope > 0
    else:  # lower
        improving = raw_slope < 0

    return {"slope": raw_slope, "direction": direction, "improving": improving}


def analyze_trends(sessions):
    """Per-metric trend across sessions, oldest first.

    `sessions` is a list of swing-lists (each a session's swings). Returns
    {metric_key: {values, first, last, trend}} for every metric with at least
    two sessions carrying it.
    """
    out = {}
    for key, spec in METRICS.items():
        values = [session_value(s, spec) for s in sessions]
        present = [v for v in values if v is not None]
        if len(present) < 2:
            continue
        out[key] = {
            "label": spec["label"],
            "unit": spec["unit"],
            "values": values,
            "first": present[0],
            "last": present[-1],
            "trend": trend_verdict(values, spec),
        }
    return out


def format_trends(analysis, n_sessions):
    """Renders analyze_trends() output as console lines."""
    lines = ["Trend across {} sessions (oldest -> newest):".format(n_sessions)]
    if not analysis:
        lines.append("  Not enough overlapping data across sessions yet.")
        return lines

    for info in analysis.values():
        trend = info["trend"]
        if not trend:
            continue
        verdict = (
            "improving" if trend["improving"]
            else "regressing" if trend["improving"] is False
            else trend["direction"]
        )
        lines.append(
            "  {:<18} {:.2f}{} -> {:.2f}{}   {}".format(
                info["label"],
                info["first"], info["unit"].strip(),
                info["last"], info["unit"].strip(),
                verdict,
            )
        )
    return lines
