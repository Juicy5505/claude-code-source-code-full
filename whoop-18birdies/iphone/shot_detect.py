"""Infer shot locations from a GPS track, with the phone in your pocket.

WHY THIS EXISTS
---------------
Swing detection needs the phone strapped to your lead forearm — that is where a
swing is ~8x your walking motion and easy to pick out. Nobody wants to play
eighteen holes with a phone bandaged to their arm, and a WHOOP on that wrist
cannot help: it exposes heart rate over Bluetooth and no motion of any kind.

But *yardage does not need the arm at all.* You walk to your ball, you stop, you
hit it, you walk to it again. The distance the ball travelled is the distance
between where you stopped and where you stopped next. That is how Arccos and
Shot Scope measure distance too, and it works with the phone anywhere on you.

So this is the pocket path: GPS in, shot locations and distances out, no swing
sensing involved. It gives up tempo and peak force — genuinely unavailable from
a pocket — and keeps the number most golfers actually want.

WHAT IT CAN AND CANNOT DO
-------------------------
* Distances between stops: yes, to roughly GPS accuracy (a few yards).
* Which club: no. It can group distances into bands (see club_model.py), which
  is a different and weaker claim.
* Swing path, face angle, club speed: no, and no wrist or pocket sensor gives
  these. They need the club's position in space — a launch monitor.
* Putts: it flags short, clustered stops on a green rather than reporting them
  as 4-yard drives, but it cannot count them reliably.

Pure Python, no Pythonista imports, so it is testable off-device.
"""

import math

from shot_model import haversine_m, metres_to_yards

# A stop must last at least this long to be a shot. Addressing a ball takes
# several seconds; a glance at your phone does not.
MIN_STOP_S = 8.0

# Stops longer than this are FLAGGED as long waits — a tee backed up, a search
# for a ball, the halfway hut — but they are still stops.
#
# An earlier version discarded them, and that was badly wrong. A stop is not
# only a shot; it is a BOUNDARY between shots. Waiting five minutes on a tee and
# then hitting a drive still produced a drive, and dropping the stop merged the
# shot before it and the shot after it into one phantom measurement spanning
# both. In testing, a five-minute tee wait between two 251-yard drives deleted
# both of them: the surviving stops were 460 yards apart, which the transition
# rule then discarded as a walk between holes.
#
# Keeping a suspicious stop costs at worst one spurious shot, which is visible
# and flagged. Dropping one silently destroys real ones. Keep it.
MAX_STOP_S = 240.0

# Fixes within this radius of the running centre count as the same stop. Consumer
# GPS wanders several metres while genuinely stationary, so a radius much tighter
# than this splits one stop into several.
STOP_RADIUS_M = 12.0

# Past this, a "stop" is not a stand with noisy fixes — it is a walk that never
# tripped the displacement test, and there was no ball struck in it.
#
# Set well clear of both cases rather than between them. Standing with fixes at
# the 20 m accuracy limit sprawls tens of metres; walking, even slowly, covers
# 0.7 m every second, so a stop long enough to matter covers hundreds. Nothing
# real lands near 40 m, which is what makes it a safe place to cut.
DRIFT_CEILING_M = 40.0

# Fixes worse than this are noise, not position. A 50 m fix under tree cover
# would invent a 50 m shot.
MAX_ACCURACY_M = 20.0

# You are stationary if you have moved less than STATIONARY_DISPLACEMENT_M over
# STATIONARY_WINDOW_S. These two numbers are what separate standing over a ball
# from walking to it, and the margin is comfortable: a golfer walks at roughly
# 1.2-1.4 m/s, so ten seconds of walking covers 12-14 m, while ten seconds of
# standing still moves you only as far as GPS noise wanders — three to five
# metres on a modern phone.
STATIONARY_WINDOW_S = 10.0
STATIONARY_DISPLACEMENT_M = 8.0

# Consecutive stops closer together than this are pitches, chips or putts, not
# full shots. Reported, but flagged rather than mixed into the club statistics,
# where a 40-yard pitch would drag a wedge's average down.
SHORT_SHOT_YD = 50.0

# The resolution floor, and the honest limit of this whole method.
#
# A stop is identified by having moved less than STATIONARY_DISPLACEMENT_M over
# STATIONARY_WINDOW_S. A shot shorter than roughly that distance therefore never
# breaks the stationary test at all: you stand, chip twelve metres, walk after it
# and stand again, and the entire sequence reads as one continuous stop. The shot
# is not mis-measured, it is invisible.
#
# This is not a tuning problem to be solved with better constants — tighten the
# window and ordinary GPS jitter starts fabricating stops instead. It is why the
# commercial trackers that do measure the short game (Arccos, Shot Scope) put a
# sensor in the grip or the club rather than relying on where the player stood.
#
# Shots between this floor and SHORT_SHOT_YD are resolved but under-measured by
# roughly ten percent, because the stop boundaries blur by half a window at each
# end. At full-shot distances that blur is proportionally negligible.
MIN_RESOLVABLE_YD = 33.0

# A gap larger than this between stops is a walk between holes, or the drive
# from the range — not a shot anyone hit.
MAX_SHOT_YD = 450.0


class Stop:
    """A place you stood still long enough to have hit a shot."""

    __slots__ = ("start_t", "end_t", "lat", "lon", "n_fixes", "long_wait", "drifted")

    def __init__(self, start_t, end_t, lat, lon, n_fixes, long_wait=False,
                 drifted=False):
        self.start_t = start_t
        self.end_t = end_t
        self.lat = lat
        self.lon = lon
        self.n_fixes = n_fixes
        # True when the stop ran past MAX_STOP_S. Still a stop, still a shot
        # boundary — just one worth looking at twice.
        self.long_wait = long_wait
        # True when the fixes sprawled further than STOP_RADIUS_M. Same idea:
        # the position is less trustworthy than usual, but the stop is real and
        # deleting it costs two shots rather than one. See `flush`.
        self.drifted = drifted

    @property
    def duration_s(self):
        return self.end_t - self.start_t

    def as_dict(self):
        return {
            "start_t": round(self.start_t, 3),
            "end_t": round(self.end_t, 3),
            "duration_s": round(self.duration_s, 1),
            "latitude": self.lat,
            "longitude": self.lon,
            "n_fixes": self.n_fixes,
            "long_wait": self.long_wait,
            "drifted": self.drifted,
        }

    def __repr__(self):  # pragma: no cover - debugging aid
        return "Stop({:.5f}, {:.5f}, {:.0f}s, n={})".format(
            self.lat, self.lon, self.duration_s, self.n_fixes
        )


def _usable(fix, max_accuracy_m):
    """A fix is usable only if it carries a real position and a sane accuracy.

    iOS reports a NEGATIVE horizontal accuracy when the fix is invalid, which is
    the trap here: a naive `accuracy <= 20` test treats -1 as excellent and
    happily builds a round out of garbage coordinates.
    """
    lat = fix.get("latitude")
    lon = fix.get("longitude")
    if lat is None or lon is None:
        return False
    if not (math.isfinite(lat) and math.isfinite(lon)):
        return False
    if not (-90.0 <= lat <= 90.0 and -180.0 <= lon <= 180.0):
        return False
    accuracy = fix.get("horizontal_accuracy")
    if accuracy is None:
        return True  # unknown accuracy is not the same as bad accuracy
    if not math.isfinite(accuracy) or accuracy < 0:
        return False
    return accuracy <= max_accuracy_m


def _stationary_flags(fixes, window_s, max_displacement_m):
    """Mark each fix as stationary or not, by displacement over a time window.

    This is the load-bearing decision in the whole module, and the obvious
    approach does not work. Clustering fixes around a running mean cannot
    separate standing from walking: while walking, each fix is only a metre or
    two from the drifting centre, so the cluster keeps absorbing fixes and only
    breaks when the *mean* has itself travelled — manufacturing a "stop" every
    fifteen seconds along a perfectly ordinary walk down the fairway.

    Displacement over a fixed window has no such blind spot. Standing still for
    ten seconds moves you a few metres of GPS noise; walking for ten seconds
    moves you twelve to fourteen. The two do not overlap, and the test does not
    care how the noise is shaped.
    """
    n = len(fixes)
    flags = [False] * n
    j = 0
    for i in range(n):
        if j < i:
            j = i
        while j < n and fixes[j]["t"] - fixes[i]["t"] < window_s:
            j += 1
        if j >= n:
            break  # no full window remains; the tail is decided by earlier windows
        moved = haversine_m(
            fixes[i]["latitude"], fixes[i]["longitude"],
            fixes[j]["latitude"], fixes[j]["longitude"],
        )
        if moved <= max_displacement_m:
            # The whole window was stationary, not just its first sample —
            # marking only `i` would report a 15 s stop as lasting 5 s.
            for k in range(i, j + 1):
                flags[k] = True
    return flags


def find_stops(
    fixes,
    min_stop_s=MIN_STOP_S,
    max_stop_s=MAX_STOP_S,
    radius_m=STOP_RADIUS_M,
    max_accuracy_m=MAX_ACCURACY_M,
    window_s=STATIONARY_WINDOW_S,
    max_displacement_m=STATIONARY_DISPLACEMENT_M,
    drift_ceiling_m=DRIFT_CEILING_M,
):
    """Find the places you stood still long enough to have hit a shot.

    `fixes` is a list of dicts with keys `t` (epoch seconds), `latitude`,
    `longitude` and optionally `horizontal_accuracy`, in time order.

    Two stages: decide which fixes are stationary (above), then group runs of
    them. A group's position is the mean of its fixes, so a stop is not anchored
    to whichever noisy sample happened to open it.
    """
    usable = [f for f in fixes if _usable(f, max_accuracy_m)]
    if not usable:
        return []

    flags = _stationary_flags(usable, window_s, max_displacement_m)
    stops = []
    run = []

    def flush(group):
        if not group:
            return
        duration = group[-1]["t"] - group[0]["t"]
        if duration < min_stop_s:
            return  # too brief to be addressing a ball
        lat = sum(f["latitude"] for f in group) / len(group)
        lon = sum(f["longitude"] for f in group) / len(group)
        # How far the group sprawls. A genuine stop is compact; a slow walk
        # that never tripped the displacement test sprawls for hundreds of
        # metres. Between those sits an ordinary long stand whose fixes wander
        # on GPS noise, and the three need different answers.
        spread = max(
            haversine_m(lat, lon, f["latitude"], f["longitude"]) for f in group
        )

        # Dropping anything past the radius was one rule for all three, and it
        # cost more than it saved. Stand at your ball for five minutes — a
        # halfway hut, a lost ball, a slow group ahead — and 15 m of GPS wander
        # is unremarkable while no single 10 s window ever exceeds 8 m. The stop
        # was deleted, so the shot played from it disappeared, AND the previous
        # shot was then measured to the stop after it. A 230 yd drive and a
        # 150 yd approach came back as one 287 yd drive: not a missing shot, a
        # FABRICATED one, at a distance plausible enough to keep.
        #
        # So a sprawling stop is kept and flagged, exactly as a long one is. The
        # ceiling below still drops the case the original guard was written for,
        # where the "stop" is really a walk: at walking pace even a slow one
        # covers hundreds of metres, nowhere near this.
        if spread > drift_ceiling_m:
            return
        stops.append(
            Stop(group[0]["t"], group[-1]["t"], lat, lon, len(group),
                 long_wait=duration > max_stop_s,
                 drifted=spread > radius_m)
        )

    for fix, stationary in zip(usable, flags):
        if stationary:
            run.append(fix)
        else:
            flush(run)
            run = []
    flush(run)
    return stops


def shots_from_stops(stops, max_shot_yd=MAX_SHOT_YD, short_shot_yd=SHORT_SHOT_YD):
    """Turn consecutive stops into shots with measured distances.

    Every stop but the last is a shot: you stood there, you hit it, and the next
    stop is where it finished. The last stop has no successor and therefore no
    measurable distance — reported with `distance_yd = None` rather than dropped,
    because pretending the round had one fewer shot is worse than an honest gap.
    """
    shots = []
    for i, stop in enumerate(stops):
        record = stop.as_dict()
        record["index"] = i + 1
        record["distance_yd"] = None
        record["kind"] = "unmeasured"

        if i + 1 < len(stops):
            nxt = stops[i + 1]
            yards = metres_to_yards(
                haversine_m(stop.lat, stop.lon, nxt.lat, nxt.lon)
            )
            yards = round(yards, 1)
            if yards > max_shot_yd:
                # Longer than any golf shot: this is the walk to the next tee.
                record["kind"] = "transition"
            elif yards < short_shot_yd:
                record["kind"] = "short"
                record["distance_yd"] = yards
            else:
                record["kind"] = "shot"
                record["distance_yd"] = yards
        shots.append(record)
    return shots


_STOP_KWARGS = frozenset(
    {"min_stop_s", "max_stop_s", "radius_m", "max_accuracy_m",
     "window_s", "max_displacement_m", "drift_ceiling_m"}
)
_SHOT_KWARGS = frozenset({"max_shot_yd", "short_shot_yd"})


def detect_shots(fixes, **kwargs):
    """GPS track in, shots out. The one call the logger needs.

    Unknown keywords raise rather than being dropped. An earlier version
    filtered silently, so `detect_shots(fixes, window_s=6)` — the parameter that
    actually decides what counts as standing still — was accepted, ignored, and
    ran with the default. Tuning that appears to work and does nothing is worse
    than tuning that fails.
    """
    unknown = set(kwargs) - _STOP_KWARGS - _SHOT_KWARGS
    if unknown:
        raise TypeError(
            "detect_shots() got unexpected keyword argument(s): {}. Valid: {}".format(
                ", ".join(sorted(unknown)),
                ", ".join(sorted(_STOP_KWARGS | _SHOT_KWARGS)),
            )
        )
    stop_kwargs = {k: v for k, v in kwargs.items() if k in _STOP_KWARGS}
    shot_kwargs = {k: v for k, v in kwargs.items() if k in _SHOT_KWARGS}
    return shots_from_stops(find_stops(fixes, **stop_kwargs), **shot_kwargs)


def to_session(shots, mode="pocket", sample_rate_hz=1.0):
    """Convert detected shots into the shared session schema.

    One schema, one pipeline: `round_report.py`, `club_model.py`, `trends.py`
    and `analyze.py` all read a `{"swings": [...]}` wrapper, and the ingest
    server stores one. Emitting a second, pocket-only shape would mean teaching
    every one of them about it — and would quietly diverge the moment either
    side changed.

    The fields a pocket cannot measure (peak_g, tempo) are simply absent rather
    than zero or null-filled. Every consumer already treats a missing metric as
    "no reading", which is the truth here; a zero would be a lie that averages.
    """
    swings = []
    for shot in shots:
        if shot["kind"] == "transition":
            continue  # a walk between holes is not a shot anyone played
        record = {
            "index": len(swings) + 1,
            "timestamp": _iso_local(shot["start_t"]),
            "source": "gps-stop",
            "stop_duration_s": shot["duration_s"],
            "location": {
                "latitude": shot["latitude"],
                "longitude": shot["longitude"],
                "horizontal_accuracy": None,
            },
        }
        if shot["distance_yd"] is not None:
            record["distance_yd"] = shot["distance_yd"]
        if shot["kind"] == "short":
            record["short_shot"] = True
        if shot.get("drifted"):
            # The fixes at this stop sprawled further than a compact stand. The
            # shot is real — it used to be deleted, which merged two shots into
            # one fabricated long one — but its position is the weakest in the
            # round, so both its distance and the previous one are soft.
            record["drifted"] = True
        if shot.get("long_wait"):
            # You stood here a long time before hitting. The shot is real, but
            # a long wait is also how a halfway hut or a lost-ball search looks,
            # so it is worth being able to see them.
            record["long_wait"] = True
        if shot.get("hr_bpm") is not None:
            # Live WHOOP HR stamped onto the stop (see hr_monitor.attach_hr_to_shots).
            # Absent when no broadcast was running — never zero-filled.
            record["hr_bpm"] = shot["hr_bpm"]
        swings.append(record)

    return {
        "mode": mode,
        "sample_rate_hz": sample_rate_hz,
        "auto_threshold": False,
        "detector": "gps-stop-detection",
        "min_resolvable_yd": MIN_RESOLVABLE_YD,
        "swings": swings,
    }


def _iso_local(epoch_seconds):
    """Local-time ISO stamp, matching what the swing logger writes.

    Local rather than UTC, deliberately: the ingest server files a session under
    its first record's calendar date, and every WHOOP join is on the local date.
    An evening round stamped in UTC lands on tomorrow and silently falls out of
    both.
    """
    import time

    return time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(epoch_seconds))


def summarise(shots):
    """Round-level numbers from detected shots. None when there is nothing to say."""
    full = [s["distance_yd"] for s in shots if s["kind"] == "shot"]
    short = [s for s in shots if s["kind"] == "short"]
    transitions = [s for s in shots if s["kind"] == "transition"]
    long_waits = [s for s in shots if s.get("long_wait")]

    if not full:
        return {
            "n_shots": 0,
            "n_short": len(short),
            "n_transitions": len(transitions),
            "n_long_waits": len(long_waits),
            "longest_yd": None,
            "mean_yd": None,
            "total_yd": None,
        }

    return {
        "n_shots": len(full),
        "n_short": len(short),
        "n_transitions": len(transitions),
        "n_long_waits": len(long_waits),
        "longest_yd": round(max(full), 1),
        "mean_yd": round(sum(full) / len(full), 1),
        "total_yd": round(sum(full), 1),
    }


def format_report(shots):
    """A human read-out of a pocket-tracked round."""
    stats = summarise(shots)
    lines = []

    if not stats["n_shots"]:
        lines.append("No shots resolved from the GPS track.")
        lines.append("")
        lines.append("Most likely causes, in order:")
        lines.append("  * GPS was not running, or the fixes carry no accuracy field.")
        lines.append("  * You never stood still for {:.0f}s — the stop test never".format(MIN_STOP_S))
        lines.append("    fired. Ready over the ball a beat longer.")
        lines.append("  * Accuracy was worse than {:.0f} m throughout (heavy tree".format(MAX_ACCURACY_M))
        lines.append("    cover, or the phone denied precise location).")
        return "\n".join(lines)

    lines.append("Shots measured by GPS, stop to stop")
    lines.append("-" * 44)
    for shot in shots:
        if shot["kind"] == "transition":
            continue
        distance = shot["distance_yd"]
        marker = "  (short — chip or putt)" if shot["kind"] == "short" else ""
        if distance is None:
            lines.append("  {:>3}  last stop, no distance to measure".format(shot["index"]))
        else:
            lines.append("  {:>3}  {:6.1f} yd{}".format(shot["index"], distance, marker))

    lines.append("")
    lines.append(
        "{} full shot(s), mean {:.1f} yd, longest {:.1f} yd.".format(
            stats["n_shots"], stats["mean_yd"], stats["longest_yd"]
        )
    )
    if stats["n_short"]:
        lines.append(
            "{} short stop(s) under {:.0f} yd — chips and putts, kept out of the "
            "club stats.".format(stats["n_short"], SHORT_SHOT_YD)
        )
    if stats["n_transitions"]:
        lines.append(
            "{} gap(s) over {:.0f} yd treated as walks between holes, not shots.".format(
                stats["n_transitions"], MAX_SHOT_YD
            )
        )
    if stats.get("n_long_waits"):
        lines.append(
            "{} stop(s) ran over {:.0f} min — a backed-up tee, a ball search, or the "
            "halfway hut. Kept, because a stop is a shot BOUNDARY even when it is "
            "not itself a shot.".format(stats["n_long_waits"], MAX_STOP_S / 60)
        )

    lines.append("")
    lines.append("What this method cannot see")
    lines.append(
        "  Shots under about {:.0f} yd do not appear at all. A chip and the walk".format(
            MIN_RESOLVABLE_YD
        )
    )
    lines.append("  after it read as one continuous stop, so the shot is invisible")
    lines.append("  rather than wrong. Expect your count to be short by roughly your")
    lines.append("  number of chips and putts.")
    lines.append("  Tempo, peak force, swing path, face angle and club speed need the")
    lines.append("  phone on your arm, or a launch monitor. A pocket cannot give them.")
    return "\n".join(lines)
