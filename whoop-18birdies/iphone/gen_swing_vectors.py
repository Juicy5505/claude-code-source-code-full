#!/usr/bin/env python3
"""Generate golden vectors pinning the Swift port to the Python reference.

The watch app's `SwingDetector.swift` is a hand port of `swing_metrics.py`. The
Python has 93 tests; the Swift has never been compiled, let alone run. So the
port's faithfulness has until now rested on careful reading — which found four
real bugs, and would not reliably find a fifth.

This closes that gap without needing a Swift toolchain here. It runs the Python
reference over a set of deliberately awkward motion traces, records exactly what
it produces, and writes both to a JSON fixture. The Swift test target reads the
*same* fixture and asserts the *same* outputs. One `⌘U` in Xcode then answers
"is the port faithful?" empirically, in seconds, instead of after a range
session produces numbers that look plausible and are not.

The fixture records what the reference ACTUALLY does, not what it ought to do.
That is the point: if the Python is subtly wrong, the Swift should be wrong in
exactly the same way, or the watch and the phone will disagree about the same
swing. Correcting the reference is a separate, deliberate act — change the
Python, its tests, and then regenerate.

    python3 iphone/gen_swing_vectors.py          # writes the fixture
    python3 iphone/gen_swing_vectors.py --check  # verifies it is up to date
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import swing_metrics as sm  # noqa: E402

OUT = (
    Path(__file__).resolve().parent.parent
    / "watch"
    / "WhoopGolfWatchAppTests"
    / "swing_vectors.json"
)

DT = 0.01  # 100 Hz, the rate both the watch and the phone logger run at


def at(index: int, dt: float = DT) -> float:
    """Sample time, rounded so the trace is exactly representable.

    Accumulating `t += dt` drifts, and a drifting clock would bake float noise
    into the golden values, making the Swift comparison fail for a reason that
    has nothing to do with the port.
    """
    return round(index * dt, 6)


# --------------------------------------------------------------- trace shapes


def quiet(n: int, level: float = 0.05) -> list[float]:
    return [level] * n


def ramp(n: int, lo: float, hi: float) -> list[float]:
    if n <= 1:
        return [hi] * n
    return [lo + (hi - lo) * i / (n - 1) for i in range(n)]


def spike(n: int, peak: float, base: float = 1.0) -> list[float]:
    """A downswing: accelerating into impact, then a sharp fall-off."""
    out = []
    for i in range(n):
        frac = i / max(1, n - 1)
        out.append(base + (peak - base) * (frac**2))
    return out


def build_swing(
    *,
    address_n: int,
    backswing_n: int,
    top_n: int,
    downswing_n: int,
    follow_n: int,
    peak_g: float = 12.0,
    top_dip: float = 0.20,
    walking: bool = False,
    dt: float = DT,
) -> tuple[list, int]:
    """A synthetic swing, returned with the index of its impact peak.

    `top_dip` below QUIET_G is the trap the detector must not fall into: at the
    top of the backswing the club momentarily stops, and a naive search for the
    first quiet sample mistakes that for the address position and throws the
    whole backswing away.

    `walking=True` replaces the address stillness with gait, which is the case
    that must resolve to None rather than a fabricated tempo.
    """
    mags: list[float] = []
    if walking:
        # Gait: a repeating step pattern, never sustained-quiet.
        for i in range(address_n):
            mags.append(0.55 + 0.45 * abs(math.sin(i * 0.35)))
    else:
        mags += quiet(address_n)
    mags += ramp(backswing_n, 0.4, 2.4)
    mags += quiet(top_n, top_dip)
    mags += spike(downswing_n, peak_g)
    peak_index = len(mags) - 1
    mags += ramp(follow_n, peak_g * 0.6, 0.3)

    samples = [(at(i, dt), round(m, 6), None) for i, m in enumerate(mags)]
    return samples, peak_index


def with_attitude(samples: list, sweep_rad: float = 1.4, start_rad: float = 0.0) -> list:
    """Attach a monotonic yaw sweep so attitude_sweep has something to measure.

    `start_rad` offsets the sweep so it can be made to cross the +/-pi wrap,
    which is where the naive max-minus-min reads a 45-degree turn as 359.
    """
    n = len(samples)
    out = []
    for i, (t, mag, _) in enumerate(samples):
        frac = i / max(1, n - 1)
        yaw = start_rad + sweep_rad * frac
        # Core Motion reports yaw in (-pi, pi]; reproduce that wrapping here so
        # the fixture exercises the same values a device would deliver.
        yaw = math.atan2(math.sin(yaw), math.cos(yaw))
        out.append((t, mag, (0.1 * frac, 0.2 * frac, yaw)))
    return out


def encode(samples: list) -> list:
    return [[t, m, list(a) if a else None] for t, m, a in samples]


# ------------------------------------------------------------------- the cases


def motion_start_cases() -> list[dict]:
    cases = []

    samples, peak = build_swing(
        address_n=40, backswing_n=70, top_n=6, downswing_n=25, follow_n=30
    )
    cases.append(("clean swing from a settled address", samples, peak))

    # The load-bearing case: no address stillness at all.
    samples, peak = build_swing(
        address_n=60, backswing_n=70, top_n=6, downswing_n=25, follow_n=30,
        walking=True,
    )
    cases.append(("swing taken straight out of walking", samples, peak))

    # The top-of-backswing dip must not be mistaken for address. Its quiet run
    # is 6 samples = 0.05 s, well under QUIET_RUN_S.
    samples, peak = build_swing(
        address_n=40, backswing_n=70, top_n=6, downswing_n=25, follow_n=30,
        top_dip=0.10,
    )
    cases.append(("deep pause at the top must not read as address", samples, peak))

    # A dip at the top long enough to BE a valid address run. The reference
    # accepts it; whatever it does, the Swift must do too.
    samples, peak = build_swing(
        address_n=40, backswing_n=70, top_n=20, downswing_n=25, follow_n=30,
        top_dip=0.10,
    )
    cases.append(("pause at the top long enough to qualify", samples, peak))

    # Address further back than MAX_BACKSWING_S.
    samples, peak = build_swing(
        address_n=30, backswing_n=210, top_n=6, downswing_n=25, follow_n=20
    )
    cases.append(("address beyond the 2 s lookback bound", samples, peak))

    cases.append(("peak at index 0", [(0.0, 9.0, None)], 0))
    cases.append(("two samples, peak at 1", [(0.0, 0.05, None), (0.01, 9.0, None)], 1))
    cases.append((
        "all quiet, no motion at all",
        [(at(i), 0.05, None) for i in range(60)],
        59,
    ))

    out = []
    for name, samples, peak in cases:
        out.append({
            "name": name,
            "samples": encode(samples),
            "peak": peak,
            "expect": sm.find_motion_start(samples, peak),
        })
    return out


def transition_cases() -> list[dict]:
    out = []
    specs = [
        ("clean swing", dict(address_n=40, backswing_n=70, top_n=6, downswing_n=25, follow_n=30)),
        ("short backswing", dict(address_n=40, backswing_n=8, top_n=3, downswing_n=10, follow_n=10)),
        # The reference refuses a window under three samples. Both sides of that
        # boundary are pinned, because an off-by-one here is the difference
        # between a reported tempo and an honest nil.
        ("window at the three-sample boundary", dict(address_n=20, backswing_n=1, top_n=1, downswing_n=2, follow_n=5)),
        ("window one sample under the boundary", dict(address_n=20, backswing_n=1, top_n=0, downswing_n=1, follow_n=5)),
        ("no address", dict(address_n=60, backswing_n=70, top_n=6, downswing_n=25, follow_n=30, walking=True)),
    ]
    for name, kwargs in specs:
        samples, peak = build_swing(**kwargs)
        start = sm.find_motion_start(samples, peak)
        out.append({
            "name": name,
            "samples": encode(samples),
            "peak": peak,
            "start": start,
            "expect": sm.find_transition(samples, peak, start),
        })
    return out


def analyse_cases() -> list[dict]:
    out = []

    specs = [
        ("3:1 tempo, the tour benchmark",
         dict(address_n=40, backswing_n=75, top_n=5, downswing_n=25, follow_n=30), True),
        ("2:1 tempo, quick backswing",
         dict(address_n=40, backswing_n=50, top_n=5, downswing_n=25, follow_n=30), True),
        ("4:1 tempo, slow backswing",
         dict(address_n=40, backswing_n=100, top_n=5, downswing_n=25, follow_n=30), True),
        ("gentle chip, low peak",
         dict(address_n=40, backswing_n=40, top_n=5, downswing_n=20, follow_n=20, peak_g=2.4), True),
        ("no address, must not fabricate a tempo",
         dict(address_n=60, backswing_n=70, top_n=6, downswing_n=25, follow_n=30, walking=True), False),
        ("no attitude data at all",
         dict(address_n=40, backswing_n=75, top_n=5, downswing_n=25, follow_n=30), False),
        # The yaw wrap. A rotation crossing +/-pi must report its real size, not
        # ~360 degrees. Which swings hit this depends only on the compass
        # direction you are aimed at, so it comes and goes for no visible reason.
        ("rotation crossing the +/-pi yaw wrap",
         dict(address_n=40, backswing_n=75, top_n=5, downswing_n=25, follow_n=30), "wrap"),
    ]
    for name, kwargs, attitude in specs:
        samples, peak = build_swing(**kwargs)
        if attitude == "wrap":
            samples = with_attitude(samples, start_rad=2.6)
        elif attitude:
            samples = with_attitude(samples)
        result = sm.analyse_swing(samples, peak)
        out.append({
            "name": name,
            "samples": encode(samples),
            "peak": peak,
            "expect": {
                "peak_g": result.get("peak_g"),
                "backswing_s": result.get("backswing_s"),
                "downswing_s": result.get("downswing_s"),
                "tempo_ratio": result.get("tempo_ratio"),
                "yaw_deg": (result.get("attitude_sweep") or {}).get("yaw_deg"),
                "tempo_frames": sm.tour_tempo_frames(
                    result.get("backswing_s"), result.get("downswing_s")
                ),
            },
        })
    return out


def frames_cases() -> list[dict]:
    """Tempo-in-frames, including the exact .5 boundaries.

    These are not academic. Python's format rounds half-to-even and Swift's
    `.rounded()` rounds half-away-from-zero, so a 0.75 s backswing — dead centre
    of the elite 0.7-0.9 s range — is 22 frames on the phone and 23 on the
    watch. Same swing, two headline numbers.
    """
    pairs = [
        (0.75, 0.25),   # 22.5 / 7.5  — both exact halves
        (0.35, 0.25),   # 10.5 / 7.5
        (0.65, 0.25),   # 19.5 / 7.5
        (0.85, 0.35),   # 25.5 / 10.5
        (0.716, 0.239), # ordinary values, no boundary
        (0.8, 0.267),
        (0.7, 0.233),
        (0.0, 0.0),
    ]
    out = [
        {"backswing_s": b, "downswing_s": d, "expect": sm.tour_tempo_frames(b, d)}
        for b, d in pairs
    ]
    out.append({"backswing_s": None, "downswing_s": 0.25, "expect": None})
    out.append({"backswing_s": 0.75, "downswing_s": None, "expect": None})
    return out


def shot_distance_cases() -> list[dict]:
    """Pins the watch's haversine port to the tested Python.

    The watch now measures shots itself rather than only recording positions,
    so the geodesy runs in two languages and has to agree. Includes the poles,
    the antimeridian and identical points, because those are where a
    hand-ported haversine goes wrong.
    """
    import shot_model as sm2

    pairs = [
        ("a drive, north", 32.8973, -117.2531, 32.89936, -117.2531),
        ("a wedge, east", 32.8973, -117.2531, 32.8973, -117.25165),
        ("a diagonal approach", 32.8973, -117.2531, 32.89836, -117.25215),
        ("identical points", 32.8973, -117.2531, 32.8973, -117.2531),
        ("across the antimeridian", 1.0, 179.9995, 1.0, -179.9995),
        ("near the north pole", 89.999, 0.0, 89.999, 180.0),
        ("southern hemisphere", -33.8688, 151.2093, -33.8700, 151.2093),
        ("a full hole apart", 32.8973, -117.2531, 32.9010, -117.2531),
    ]
    out = []
    for name, lat1, lon1, lat2, lon2 in pairs:
        metres = sm2.haversine_m(lat1, lon1, lat2, lon2)
        out.append({
            "name": name,
            "from": [lat1, lon1],
            "to": [lat2, lon2],
            "expect_m": round(metres, 4),
            "expect_yd": round(sm2.metres_to_yards(metres), 4),
        })

    # And the full annotation pass, including the cases that must yield null.
    swings = [
        {"index": 1, "location": {"latitude": 32.8973, "longitude": -117.2531}},
        {"index": 2, "location": {"latitude": 32.89936, "longitude": -117.2531}},
        {"index": 3, "location": None},
        {"index": 4, "location": {"latitude": 32.9010, "longitude": -117.2531}},
        {"index": 5, "location": {"latitude": 32.9010, "longitude": None}},
        {"index": 6, "location": {"latitude": 32.9020, "longitude": -117.2531}},
    ]
    sm2.shot_distances(swings)
    out.append({
        "name": "annotation pass with gaps",
        "swings": [
            {"index": s["index"], "location": s["location"],
             "distance_yd": s["distance_yd"]}
            for s in swings
        ],
    })
    return out


def threshold_cases() -> list[dict]:
    """AdaptiveThreshold state at each step, so a divergence is localised."""
    out = []

    def run(name, observations, probes, **kwargs):
        det = sm.AdaptiveThreshold(**kwargs)
        trace = []
        for mag in observations:
            det.observe(mag)
            trace.append({
                "baseline": det.baseline(),
                "threshold": round(det.threshold(), 9),
                "ready": det.ready(),
            })
        out.append({
            "name": name,
            "init": kwargs,
            "observations": observations,
            "trace": trace,
            "probes": [{"mag": p, "expect": det.is_swing(p)} for p in probes],
        })

    # Small window so the cached-median cadence is exercised in few steps.
    run("stillness then a swing",
        quiet(40, 0.05) + [11.0], [0.1, 1.4, 1.6, 11.0],
        window_seconds=0.4, sample_hz=100, recompute_every=5)

    run("walking baseline",
        [round(0.55 + 0.45 * abs(math.sin(i * 0.35)), 6) for i in range(60)],
        [1.0, 1.5, 2.0, 3.0, 12.0],
        window_seconds=0.4, sample_hz=100, recompute_every=5)

    # Even-length window: median is the mean of the two middle values.
    run("even-length window median",
        [1.0, 2.0, 3.0, 4.0], [1.0, 4.0, 8.0],
        window_seconds=0.32, sample_hz=100, recompute_every=1)

    # Window overflow: the oldest samples must be dropped.
    run("window overflows and drops the oldest",
        [10.0] * 20 + [0.1] * 40, [0.2, 1.4, 1.6],
        window_seconds=0.4, sample_hz=100, recompute_every=1)

    # Not enough history: is_swing must stay False however large the magnitude.
    run("below the readiness bar",
        [0.05] * 3, [50.0],
        window_seconds=10.0, sample_hz=100, recompute_every=25)

    # A stale cached median: recompute_every larger than the observation count.
    run("cached median goes stale",
        quiet(10, 0.05) + [9.0] * 10, [1.4, 1.6, 9.0],
        window_seconds=0.4, sample_hz=100, recompute_every=100)

    return out


def consistency_cases() -> list[dict]:
    sets = [
        ("three tempos", [3.0, 3.2, 2.8]),
        ("identical values, zero spread", [3.0, 3.0, 3.0]),
        ("single value", [3.0]),
        ("empty", []),
        ("with a None mixed in", [3.0, None, 3.4]),
    ]
    out = []
    for name, values in sets:
        swings = [{"tempo_ratio": v} for v in values]
        out.append({
            "name": name,
            "values": values,
            "expect": sm.consistency(swings, "tempo_ratio"),
        })
    return out


def verdict_cases() -> list[dict]:
    return [
        {"ratio": r, "expect": sm.tempo_verdict(r)}
        for r in [None, 1.0, 2.39, 2.4, 2.41, 3.0, 3.59, 3.6, 3.61, 5.0,
                  float("inf"), float("nan")]
    ]


# --------------------------------------------------------------------- driver


def build() -> dict:
    return {
        "_comment": (
            "Golden vectors generated from iphone/swing_metrics.py, the tested "
            "reference. The Swift port must reproduce every value here exactly. "
            "Regenerate with: python3 iphone/gen_swing_vectors.py"
        ),
        "reference": "iphone/swing_metrics.py",
        "sample_rate_hz": int(round(1 / DT)),
        "constants": {
            "quietG": sm.QUIET_G,
            "maxBackswingS": sm.MAX_BACKSWING_S,
            "quietRunS": sm.QUIET_RUN_S,
            "tourTempo": sm.TOUR_TEMPO,
            "tourTempoFps": sm.TOUR_TEMPO_FPS,
        },
        "motionStart": motion_start_cases(),
        "transition": transition_cases(),
        "analyse": analyse_cases(),
        "frames": frames_cases(),
        "shotDistance": shot_distance_cases(),
        "threshold": threshold_cases(),
        "consistency": consistency_cases(),
        "verdict": verdict_cases(),
    }


def serialise(data: dict) -> str:
    def default(o):
        if isinstance(o, float) and not math.isfinite(o):
            # JSON has no Infinity/NaN. These only appear in verdict inputs,
            # which the Swift side reconstructs from the sentinel.
            return {"__float__": "inf" if o > 0 else ("-inf" if o < 0 else "nan")}
        raise TypeError(repr(o))

    # allow_nan=False so a non-finite value is caught here rather than becoming
    # invalid JSON that no other language will parse.
    return json.dumps(data, indent=2, allow_nan=False, default=default) + "\n"


def sanitise(value):
    """Replace non-finite floats with a portable sentinel, recursively."""
    if isinstance(value, float) and not math.isfinite(value):
        return {"__float__": "inf" if value > 0 else ("-inf" if value < 0 else "nan")}
    if isinstance(value, dict):
        return {k: sanitise(v) for k, v in value.items()}
    if isinstance(value, list):
        return [sanitise(v) for v in value]
    return value


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true",
                        help="fail if the committed fixture is stale")
    args = parser.parse_args()

    data = sanitise(build())
    text = json.dumps(data, indent=2, allow_nan=False) + "\n"

    if args.check:
        if not OUT.exists():
            print(f"missing: {OUT}", file=sys.stderr)
            return 1
        if OUT.read_text(encoding="utf-8") != text:
            print(f"stale: {OUT}\n  regenerate with: python3 {Path(__file__).name}",
                  file=sys.stderr)
            return 1
        print(f"up to date: {OUT}")
        return 0

    OUT.parent.mkdir(parents=True, exist_ok=True)
    tmp = OUT.with_suffix(".json.tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, OUT)

    counts = {k: len(v) for k, v in data.items() if isinstance(v, list)}
    total = sum(counts.values())
    print(f"wrote {OUT}")
    for name, n in counts.items():
        print(f"  {name:<14} {n:>3} case(s)")
    print(f"  {'total':<14} {total:>3}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
