"""Shot distance, swing-to-distance fitting, and ball flight trajectories.

Deliberately free of Pythonista imports so it can be tested off-device. The
phone-only parts live in swing_logger.py (sensors) and ball_flight.py (drawing).
"""

import math

# --- Geometry ----------------------------------------------------------------

EARTH_RADIUS_M = 6_371_008.8


def haversine_m(lat1, lon1, lat2, lon2):
    """Great-circle distance in metres between two WGS84 points."""
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * EARTH_RADIUS_M * math.asin(math.sqrt(a))


def metres_to_yards(m):
    return m / 0.9144


def shot_distances(swings):
    """Annotates each swing with the distance to the following swing.

    This is how consumer shot trackers measure a shot: you walk to your ball,
    so the straight line from where you swung to where you swung next is the
    shot. The final swing of a round has no successor and stays None — as does
    any swing missing a GPS fix.
    """
    for i, swing in enumerate(swings):
        swing["distance_m"] = None
        swing["distance_yd"] = None

        here = swing.get("location")
        nxt = swings[i + 1].get("location") if i + 1 < len(swings) else None
        if not here or not nxt:
            continue
        # Guard both coordinates on both fixes. latitude and longitude are read
        # independently from the GPS dict, so one can be present while the other
        # is None; a lat-only guard would then pass None longitude into
        # haversine and crash the whole round's distance computation.
        if (
            here.get("latitude") is None
            or here.get("longitude") is None
            or nxt.get("latitude") is None
            or nxt.get("longitude") is None
        ):
            continue

        metres = haversine_m(
            here["latitude"], here["longitude"], nxt["latitude"], nxt["longitude"]
        )
        swing["distance_m"] = round(metres, 1)
        swing["distance_yd"] = round(metres_to_yards(metres), 1)
    return swings


# --- Fitting swing intensity to measured distance ----------------------------


def linear_fit(xs, ys):
    """Least-squares slope/intercept plus r-squared. None if underdetermined."""
    n = len(xs)
    if n < 3:
        return None
    mx = sum(xs) / n
    my = sum(ys) / n
    sxx = sum((x - mx) ** 2 for x in xs)
    if sxx == 0:
        return None
    sxy = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    slope = sxy / sxx
    intercept = my - slope * mx

    syy = sum((y - my) ** 2 for y in ys)
    if syy == 0:
        return None
    r2 = (sxy * sxy) / (sxx * syy)
    return {"slope": slope, "intercept": intercept, "r2": r2, "n": n}


def fit_swings(swings):
    """Fits peak swing magnitude to measured carry, over swings that have both."""
    xs, ys = [], []
    for swing in swings:
        peak = swing.get("peak_g")
        dist = swing.get("distance_yd")
        if peak is None or dist is None:
            continue
        # A "shot" under ~20 yards is usually a putt or a walk between
        # detections, not a struck shot; including them flattens the fit.
        if dist < 20:
            continue
        xs.append(peak)
        ys.append(dist)
    return linear_fit(xs, ys)


def predict_distance(fit, peak_g):
    """Predicted carry in yards for a swing, or None without a usable fit."""
    if not fit:
        return None
    return max(0.0, fit["slope"] * peak_g + fit["intercept"])


# --- Ball flight -------------------------------------------------------------

GRAVITY = 9.80665
BALL_MASS_KG = 0.04593        # R&A/USGA maximum
BALL_RADIUS_M = 0.021335      # 42.67 mm diameter
AIR_DENSITY = 1.225
DRAG_COEFFICIENT = 0.25       # dimpled ball in its normal Reynolds range

# Backspin is what makes a golf ball fly. Lift from spin roughly doubles carry
# versus a drag-only projectile, so omitting it does not merely soften the
# shape — it demands absurd launch speeds (a 250 yd carry would need ~250 mph
# instead of ~150) and puts a 300 yd drive out of reach entirely.
#
# Spin cannot be measured from an arm-worn phone, so this is an assumption, and
# a stated one: a typical driver figure. The trajectory SHAPE therefore carries
# this assumption. The RANGE does not — launch speed is solved to match a
# distance you actually measured over GPS.
DEFAULT_BACKSPIN_RPM = 2700.0


def _area():
    return math.pi * BALL_RADIUS_M ** 2


def _lift_coefficient(speed_ms, spin_rad_s):
    """Empirical Cl from the spin parameter S = omega * r / v.

    Cl = 0.32 * S**0.35 tracks published golf-ball wind-tunnel data across the
    range these flights occupy (Cl roughly 0.12-0.25).
    """
    if speed_ms <= 0.01:
        return 0.0
    s = spin_rad_s * BALL_RADIUS_M / speed_ms
    return 0.32 * (s ** 0.35)


def simulate(speed_ms, launch_deg, spin_rpm=DEFAULT_BACKSPIN_RPM, dt=0.002, max_t=15.0):
    """Integrates a ball flight with quadratic drag and Magnus lift.

    Returns [(x, y), ...] in metres. Spin is held constant; real spin decays
    over the flight, which shortens carry slightly at the top end.
    """
    angle = math.radians(launch_deg)
    vx = speed_ms * math.cos(angle)
    vy = speed_ms * math.sin(angle)
    spin = spin_rpm * 2 * math.pi / 60.0
    coeff = 0.5 * AIR_DENSITY * _area() / BALL_MASS_KG

    x = y = t = 0.0
    path = [(0.0, 0.0)]

    while t < max_t:
        v = math.hypot(vx, vy)
        if v < 1e-6:
            break

        drag = coeff * DRAG_COEFFICIENT * v
        lift = coeff * _lift_coefficient(v, spin) * v
        # Lift acts perpendicular to velocity; for backspin that is (-vy, vx)
        # normalised, which points upward for a ball travelling forward.
        ax = -drag * vx - lift * vy
        ay = -GRAVITY - drag * vy + lift * vx

        vx += ax * dt
        vy += ay * dt
        x += vx * dt
        y += vy * dt
        t += dt

        if y <= 0:
            # Interpolate the landing point so range doesn't quantise to dt.
            prev_x, prev_y = path[-1]
            if prev_y > 0:
                frac = prev_y / (prev_y - y)
                x = prev_x + (x - prev_x) * frac
            path.append((x, 0.0))
            break
        path.append((x, y))

    return path


def carry_m(speed_ms, launch_deg, spin_rpm=DEFAULT_BACKSPIN_RPM):
    return simulate(speed_ms, launch_deg, spin_rpm)[-1][0]


def solve_launch_speed(
    target_carry_m, launch_deg, spin_rpm=DEFAULT_BACKSPIN_RPM, tolerance_m=0.5
):
    """Finds the launch speed whose carry matches a measured distance.

    Bisection: carry rises monotonically with speed at fixed angle and spin, so
    this converges. Returns None if the target is beyond the bracket.
    """
    lo, hi = 1.0, 120.0
    if carry_m(hi, launch_deg, spin_rpm) < target_carry_m:
        return None

    for _ in range(60):
        mid = (lo + hi) / 2
        reach = carry_m(mid, launch_deg, spin_rpm)
        if abs(reach - target_carry_m) <= tolerance_m:
            return mid
        if reach < target_carry_m:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


def trajectory_for_distance(
    distance_yd, launch_deg=13.0, spin_rpm=DEFAULT_BACKSPIN_RPM
):
    """Ball flight whose carry matches a measured distance.

    Range is your real GPS-measured number. Shape depends on the assumed launch
    angle and spin, neither of which a phone on your arm can measure.
    """
    target_m = distance_yd * 0.9144
    speed = solve_launch_speed(target_m, launch_deg, spin_rpm)
    if speed is None:
        return None, None
    return simulate(speed, launch_deg, spin_rpm), speed
