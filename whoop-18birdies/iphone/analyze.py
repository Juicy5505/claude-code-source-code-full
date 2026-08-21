"""One entry point for reading logged sessions off-device.

    python3 analyze.py session.json                 # full report for one session
    python3 analyze.py session.json whoop.json       # + WHOOP physiology join
    python3 analyze.py s1.json s2.json s3.json ...    # trend across many sessions

A single log gets the full round report (distance, clubs, tempo, fatigue, and
the WHOOP join when a cache is given). Several logs, oldest first, get the
cross-session trend: whether tempo, consistency, distance and heart rate are
improving over time.

The one-vs-many split is decided by how many of the arguments are session logs
(a file whose JSON carries a "swings" list). A lone extra file that is a WHOOP
cache is treated as physiology for a single-session report.
"""

import json
import sys

from round_report import gps_warning_of, load_session, report, round_date
from trends import analyze_trends, format_trends


def is_session_log(path):
    """True if the file looks like a swing log (has a swings list)."""
    try:
        with open(path) as handle:
            data = json.load(handle)
    except (IOError, ValueError):
        return False
    if isinstance(data, list):
        return True
    return isinstance(data, dict) and isinstance(data.get("swings"), list)


def main(argv):
    if not argv:
        print(__doc__)
        return 1

    session_paths = [p for p in argv if is_session_log(p)]
    other_paths = [p for p in argv if p not in session_paths]

    if not session_paths:
        print("None of those files look like session logs (no 'swings' list).")
        return 1

    if len(session_paths) == 1:
        # Single session: full report, with a WHOOP cache if one was passed.
        cache = other_paths[0] if other_paths else None
        swings, meta = load_session(session_paths[0])
        report(swings, cache, meta)
        return 0

    # Many sessions: trend analysis, ordered oldest -> newest by round date so
    # the direction of travel is meaningful regardless of argument order.
    loaded = [(p,) + load_session(p) for p in session_paths]
    loaded.sort(key=lambda row: round_date(row[1]) or "")

    # A session whose GPS came from the paired phone contributes a real tempo
    # and a real swing force, but its distances measure a cart. Stripping only
    # `distance_yd` keeps the session in the tempo and heart-rate trends while
    # removing it from the distance one — dropping the whole session would
    # throw away good data, and keeping it whole would put cart movement into a
    # line the user reads as "am I hitting it further".
    flagged = []
    sessions = []
    for path, swings, meta in loaded:
        if gps_warning_of(meta):
            flagged.append(path)
            sessions.append([
                {k: v for k, v in s.items() if k != "distance_yd"} for s in swings
            ])
        else:
            sessions.append(swings)

    print("Sessions, oldest to newest:")
    for path, swings, _ in loaded:
        print("  {}  ({} swings)".format(round_date(swings) or "undated", len(swings)))
    print("")

    if flagged:
        print("GPS PROBLEM in {} of {} session(s):".format(len(flagged), len(loaded)))
        for path in flagged:
            print("  {}".format(path))
        print("  The watch was reporting the paired iPhone's position, so those")
        print("  distances measure the cart. They are excluded from the distance")
        print("  trend below; tempo, swing force and heart rate still include them.")
        print("")

    for line in format_trends(analyze_trends(sessions), len(sessions)):
        print(line)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
