"""Full round analysis: swing mechanics, distances, and the WHOOP join.

Runs off-device. Takes the swings.json a phone produced and, optionally, the
WHOOP cache the TypeScript toolkit writes, and answers the question WHOOP can
actually speak to on a golf course: does your body fade over 18 holes, and is
it worse on days you turned up under-recovered.

    python3 round_report.py swings.json [whoop-cache.json]
"""

import json
import sys

from club_model import analyze_clubs, format_club_report
from swing_metrics import consistency, fatigue_split, tempo_verdict

# --- Loading -----------------------------------------------------------------


def load_swings(path):
    with open(path) as handle:
        data = json.load(handle)
    # Accept either the logger's wrapper or a bare list.
    return data.get("swings", data) if isinstance(data, dict) else data


def local_date(iso_timestamp):
    return iso_timestamp[:10] if iso_timestamp else None


def round_date(swings):
    """The calendar date the round was played, for joining to WHOOP."""
    for swing in swings:
        date = local_date(swing.get("timestamp"))
        if date:
            return date
    return None


def whoop_day(cache_path, date):
    """Recovery, sleep and strain for a date, from the toolkit's WHOOP cache.

    Mirrors the TypeScript indexer: cycles carry the local date via their
    timezone offset, recoveries attach to a cycle, and sleep attaches to a
    recovery. Returns None when the date is not in the cache.
    """
    try:
        with open(cache_path) as handle:
            cache = json.load(handle)
    except (IOError, ValueError):
        return None

    cycle_dates = {}
    day_strain = {}
    for cycle in cache.get("cycles", []):
        start = cycle.get("start", "")
        offset = cycle.get("timezone_offset", "+00:00")
        d = _shift_date(start, offset)
        cycle_dates[cycle.get("id")] = d
        if cycle.get("score_state") == "SCORED" and cycle.get("score"):
            day_strain[d] = cycle["score"].get("strain")

    sleeps = {s.get("id"): s for s in cache.get("sleeps", [])}

    for recovery in cache.get("recoveries", []):
        if cycle_dates.get(recovery.get("cycle_id")) != date:
            continue
        if recovery.get("score_state") != "SCORED" or not recovery.get("score"):
            continue

        out = {
            "recovery": recovery["score"].get("recovery_score"),
            "hrv_ms": recovery["score"].get("hrv_rmssd_milli"),
            "resting_hr": recovery["score"].get("resting_heart_rate"),
            "day_strain": day_strain.get(date),
        }

        sleep = sleeps.get(recovery.get("sleep_id"))
        stages = (sleep or {}).get("score", {}).get("stage_summary")
        if stages:
            asleep_ms = (
                stages["total_in_bed_time_milli"] - stages["total_awake_time_milli"]
            )
            out["sleep_hours"] = round(asleep_ms / 3_600_000, 1)
        return out

    return None


def _shift_date(iso, offset):
    """Local calendar date for a UTC instant plus a '+HH:MM' offset."""
    import datetime

    try:
        base = datetime.datetime.strptime(iso[:19], "%Y-%m-%dT%H:%M:%S")
    except (ValueError, TypeError):
        return iso[:10] if iso else None

    sign = -1 if offset.strip().startswith("-") else 1
    digits = offset.strip().lstrip("+-").replace(":", "")
    if len(digits) < 4:
        return base.date().isoformat()
    minutes = sign * (int(digits[:2]) * 60 + int(digits[2:4]))
    return (base + datetime.timedelta(minutes=minutes)).date().isoformat()


# --- Reporting ---------------------------------------------------------------


def section(title):
    print("\n" + title)
    print("-" * len(title))


def report(swings, cache_path=None):
    if not swings:
        print("No swings in that log.")
        return

    date = round_date(swings)
    print("Round report — {}".format(date or "undated"))
    print("{} swings detected".format(len(swings)))

    measured = [s for s in swings if s.get("distance_yd") is not None]

    section("Distance")
    if measured:
        dists = [s["distance_yd"] for s in measured]
        print("  shots measured : {}".format(len(dists)))
        print("  longest        : {:.0f} yd".format(max(dists)))
        print("  average        : {:.0f} yd".format(sum(dists) / len(dists)))
        spread = consistency(measured, "distance_yd")
        if spread:
            print("  spread         : {:.0f} yd stdev".format(spread["stdev"]))

        club_report = analyze_clubs([s["distance_yd"] for s in measured])
        if len(club_report["bands"]) >= 2:
            print("")
            for line in format_club_report(club_report):
                print("  " + line)
    else:
        print("  none — distance needs GPS on two consecutive swings.")

    section("Tempo")
    tempo = consistency(swings, "tempo_ratio")
    if tempo:
        print("  average        : {:.2f}:1 over {} swings".format(tempo["mean"], tempo["n"]))
        print("  consistency    : {:.2f} stdev (cv {:.2f})".format(tempo["stdev"], tempo["cv"]))
        print("  {}".format(tempo_verdict(tempo["mean"])))
        print("  note: reads ~5% low by construction; track the trend, not the absolute.")
    else:
        print("  no readings — phases need a quiet-then-swing window.")

    section("Fatigue across the round")
    found = False
    for label, key in (("Distance", "distance_yd"), ("Tempo", "tempo_ratio"), ("Swing force", "peak_g")):
        drift = fatigue_split(swings, key)
        if not drift:
            continue
        found = True
        arrow = "down" if drift["change"] < 0 else "up"
        print(
            "  {:<12} {:>5} {:5.1f}%   {:.2f} -> {:.2f}".format(
                label, arrow, abs(drift["change_pct"]),
                drift["early_mean"], drift["late_mean"],
            )
        )
    if not found:
        print("  not enough shots yet (needs 6+ with the metric present).")

    if not cache_path:
        section("WHOOP")
        print("  no cache supplied — pass whoop-cache.json to join physiology.")
        return

    section("WHOOP for this date")
    day = whoop_day(cache_path, date)
    if not day:
        print("  no WHOOP data cached for {}. Run `wb sync`.".format(date))
        return

    for label, key, unit in (
        ("recovery", "recovery", "%"),
        ("HRV", "hrv_ms", " ms"),
        ("resting HR", "resting_hr", " bpm"),
        ("sleep", "sleep_hours", " h"),
        ("day strain", "day_strain", ""),
    ):
        value = day.get(key)
        if value is not None:
            print("  {:<12} {:.1f}{}".format(label, value, unit))

    section("Read")
    decline = fatigue_split(swings, "distance_yd")
    recovery = day.get("recovery")
    if decline and recovery is not None:
        lost = -decline["change_pct"]
        if lost > 3 and recovery < 50:
            print(
                "  You lost {:.0f}% of your distance in the back half on a {:.0f}%\n"
                "  recovery day. Worth logging more rounds to see if that pairing\n"
                "  holds — one round cannot separate fatigue from the course.".format(
                    lost, recovery
                )
            )
        elif lost > 3:
            print(
                "  Distance fell {:.0f}% late in the round despite {:.0f}% recovery,\n"
                "  so today's drop looks more like conditioning or conditions than\n"
                "  readiness.".format(lost, recovery)
            )
        else:
            print("  Distance held up across the round. No fatigue signal today.")
    else:
        print("  Need both a distance trend and WHOOP data to say anything useful.")

    print(
        "\n  One round is an anecdote. The correlation only means something across\n"
        "  many rounds — that is what the `wb report` command is for."
    )


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        raise SystemExit(1)
    swings = load_swings(sys.argv[1])
    report(swings, sys.argv[2] if len(sys.argv) > 2 else None)


if __name__ == "__main__":
    main()
