"""Infer club groupings and gapping from measured shot distances.

Given the GPS-measured carries from a round, this clusters them into the
discrete distance bands a set of clubs produces, then reports the gap between
adjacent clubs and flags two problems a golfer actually cares about:

* a gap too large to bridge with one swing (a missing or mis-gapped club);
* a band too wide (that club's distance is inconsistent).

This is inference, not ground truth — the log records a distance, not which
club hit it. It is the same idea a shot tracker uses when it auto-classifies
clubs from carry, and it is honest about being approximate.

Pure Python, no device imports, fully testable off-device.
"""

# A jump larger than this between sorted shots starts a new club band. Chosen
# to sit below a typical inter-club gap (~10-15 yd) but above the spread within
# one club (~5-8 yd). Tunable; the tradeoff is documented in cluster_distances.
DEFAULT_GAP_YD = 10.0

# A club band wider than this suggests that club's distance is not repeatable.
WIDE_BAND_YD = 18.0

# A gap between adjacent club means larger than this suggests a missing club.
LARGE_GAP_YD = 20.0


def _mean(xs):
    return sum(xs) / len(xs) if xs else float("nan")


def cluster_distances(distances, gap_threshold=DEFAULT_GAP_YD):
    """Groups shot distances into club bands by 1-D gap clustering.

    Sorts the distances and starts a new band wherever the jump from the
    previous shot exceeds `gap_threshold`. A smaller threshold splits more
    finely (risking one club into two); a larger one merges neighbours. It is
    deliberately simple and explainable rather than a black-box clusterer.

    Returns a list of bands, longest-distance first, each:
        {count, min_yd, max_yd, mean_yd, spread_yd}
    """
    clean = sorted(d for d in distances if d is not None and d >= 0)
    if not clean:
        return []

    bands = []
    current = [clean[0]]
    for d in clean[1:]:
        if d - current[-1] > gap_threshold:
            bands.append(current)
            current = [d]
        else:
            current.append(d)
    bands.append(current)

    out = []
    for band in bands:
        out.append(
            {
                "count": len(band),
                "min_yd": round(min(band), 1),
                "max_yd": round(max(band), 1),
                "mean_yd": round(_mean(band), 1),
                "spread_yd": round(max(band) - min(band), 1),
            }
        )
    out.sort(key=lambda b: b["mean_yd"], reverse=True)
    return out


def club_gaps(bands):
    """Yardage gaps between adjacent club bands, longest club downward.

    Returns a list of {from_yd, to_yd, gap_yd} for each neighbouring pair.
    """
    gaps = []
    for higher, lower in zip(bands, bands[1:]):
        gaps.append(
            {
                "from_yd": higher["mean_yd"],
                "to_yd": lower["mean_yd"],
                "gap_yd": round(higher["mean_yd"] - lower["mean_yd"], 1),
            }
        )
    return gaps


def analyze_clubs(distances, gap_threshold=DEFAULT_GAP_YD):
    """Full club report from a set of measured carries.

    Returns {bands, gaps, flags}. `flags` is human-readable notes on wide bands
    (inconsistent club) and large gaps (possible missing club). Needs at least
    two distinct bands to say anything about gapping.
    """
    bands = cluster_distances(distances, gap_threshold)
    gaps = club_gaps(bands)

    flags = []
    for band in bands:
        if band["count"] >= 3 and band["spread_yd"] > WIDE_BAND_YD:
            flags.append(
                "The {:.0f} yd group spans {:.0f} yd across {} shots — "
                "inconsistent distance control.".format(
                    band["mean_yd"], band["spread_yd"], band["count"]
                )
            )
    for gap in gaps:
        if gap["gap_yd"] > LARGE_GAP_YD:
            flags.append(
                "A {:.0f} yd gap between the {:.0f} and {:.0f} yd clubs — "
                "larger than one club should cover.".format(
                    gap["gap_yd"], gap["from_yd"], gap["to_yd"]
                )
            )

    return {"bands": bands, "gaps": gaps, "flags": flags}


def format_club_report(report):
    """Renders analyze_clubs() output as console lines."""
    lines = []
    bands = report["bands"]
    if not bands:
        lines.append("No measured distances to group into clubs.")
        return lines

    lines.append("Estimated club groupings (by carry):")
    for band in bands:
        spread = (
            "  +/-{:.0f} yd".format(band["spread_yd"] / 2)
            if band["count"] > 1
            else ""
        )
        lines.append(
            "  {:>5.0f} yd   x{}{}".format(band["mean_yd"], band["count"], spread)
        )

    if report["gaps"]:
        lines.append("")
        lines.append("Gaps:")
        for gap in report["gaps"]:
            lines.append(
                "  {:>5.0f} -> {:>3.0f} yd : {:.0f} yd".format(
                    gap["from_yd"], gap["to_yd"], gap["gap_yd"]
                )
            )

    for flag in report["flags"]:
        lines.append("  ! " + flag)
    return lines
