import { describe, expect, test } from "bun:test";
import {
  MIN_CV_N,
  MIN_SPLIT_N,
  buildFacts,
  summarise,
} from "../src/coach/facts.ts";
import { explainError, formatCoachRead, type CoachRead } from "../src/coach/coach.ts";
import type { GolfRound } from "../src/link/golfRound.ts";
import type { WatchSession } from "../src/store.ts";

/** A swing, with only the fields a given test cares about. */
function swing(
  index: number,
  fields: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    index,
    timestamp: `2026-08-18T09:${String(index % 60).padStart(2, "0")}:00-04:00`,
    peak_g: 4,
    ...fields,
  };
}

function session(
  swings: Array<Record<string, unknown>>,
  extra: Record<string, unknown> = {},
): WatchSession {
  return {
    mode: "round",
    sample_rate_hz: 100,
    swings: swings as WatchSession["swings"],
    ...extra,
  };
}

/** n swings each carrying `key`, values supplied by `at`. */
function series(n: number, key: string, at: (i: number) => number) {
  return Array.from({ length: n }, (_, i) => swing(i + 1, { [key]: at(i) }));
}

describe("summarise", () => {
  test("reports the sample it was given", () => {
    const stat = summarise([10, 20, 30, 40], 1)!;
    expect(stat.n).toBe(4);
    expect(stat.mean).toBe(25);
    expect(stat.median).toBe(25);
    expect(stat.min).toBe(10);
    expect(stat.max).toBe(40);
  });

  test("takes the midpoint of the two middle values for an even count", () => {
    expect(summarise([1, 2, 3, 10], 2)!.median).toBe(2.5);
  });

  test("withholds cv below the sample floor, because it would describe the sample", () => {
    const thin = Array.from({ length: MIN_CV_N - 1 }, (_, i) => i + 1);
    expect(summarise(thin)!.cv).toBeNull();
    expect(summarise([...thin, MIN_CV_N])!.cv).not.toBeNull();
  });

  test("is null for no readings rather than a zero that looks measured", () => {
    expect(summarise([])).toBeNull();
  });
});

describe("a GPS warning removes the distances rather than annotating them", () => {
  // The whole point of the watch app: a Series 5 reports the paired iPhone's
  // position, so with the phone in the cart every "shot" is cart-to-cart. A
  // number left in the fact sheet is a number the model can reason about, so
  // these have to be gone, not flagged.
  const swings = series(10, "distance_yd", (i) => 200 + i);
  const flagged = session(swings, {
    gps_warning: "GPS looks like your PHONE — put it in Airplane Mode",
  });

  test("drops every distance statistic", () => {
    const facts = buildFacts(flagged);
    expect(facts.fullShots).toBeNull();
    expect(facts.longestYd).toBeNull();
    expect(facts.distancesWithheld).toBe(true);
  });

  test("drops the distance fatigue split too", () => {
    // An unreliable yardage is no more usable as a trend than as a distance.
    const facts = buildFacts(flagged);
    expect(facts.splits.map((s) => s.metric)).not.toContain("distance_yd");
  });

  test("says why, and how many were dropped", () => {
    const caveat = buildFacts(flagged).caveats.join(" ");
    expect(caveat).toContain("cart");
    expect(caveat).toContain("10 measurement(s)");
  });

  test("keeps the swing metrics, which the wrist measured correctly", () => {
    // Only the POSITION was wrong. Tempo and impact force came from the
    // accelerometer and are unaffected.
    const withTempo = swings.map((s, i) => ({ ...s, tempo_ratio: 3 + i * 0.01 }));
    const facts = buildFacts(
      session(withTempo, { gps_warning: "GPS looks like your PHONE" }),
    );
    expect(facts.tempo!.n).toBe(10);
    expect(facts.peakG!.n).toBe(10);
  });

  test("still warns when the flag is set but nothing was measured anyway", () => {
    const facts = buildFacts(session(series(4, "peak_g", () => 4), {
      gps_warning: "GPS looks like your PHONE",
    }));
    expect(facts.distancesWithheld).toBe(false);
    expect(facts.caveats.join(" ")).toContain("GPS");
  });
});

describe("short shots stay out of the bag statistics", () => {
  test("chips do not drag the distance mean down", () => {
    // Left in, a cluster of 20 yd chips reads as a club band, and the gap up to
    // the next real club looks like a missing wedge that is not missing.
    const full = series(6, "distance_yd", () => 200);
    const chips = Array.from({ length: 4 }, (_, i) =>
      swing(100 + i, { distance_yd: 20, short_shot: true }),
    );
    const facts = buildFacts(session([...full, ...chips]));
    expect(facts.fullShots!.n).toBe(6);
    expect(facts.fullShots!.mean).toBe(200);
    expect(facts.shortShots).toBe(4);
  });
});

describe("fatigue splits refuse to over-read a small round", () => {
  test("no split until both halves clear the floor", () => {
    const thin = 2 * (MIN_SPLIT_N - 1);
    const facts = buildFacts(session(series(thin, "peak_g", () => 4)));
    expect(facts.splits).toHaveLength(0);
  });

  test("a split appears once both halves have enough", () => {
    const enough = 2 * MIN_SPLIT_N;
    const facts = buildFacts(session(series(enough, "peak_g", () => 4)));
    expect(facts.splits.map((s) => s.metric)).toContain("peak_g");
  });

  test("reports the direction and size of a real decline", () => {
    // 12 swings: 100 g for the first six, 80 for the last six. A 20% drop.
    const swings = series(12, "peak_g", (i) => (i < 6 ? 100 : 80));
    const split = buildFacts(session(swings)).splits.find(
      (s) => s.metric === "peak_g",
    )!;
    expect(split.firstHalf).toBe(100);
    expect(split.secondHalf).toBe(80);
    expect(split.changePct).toBe(-20);
    expect(split.n).toBe(6);
  });

  test("splits the swings in half, not the readings", () => {
    // 24 swings; only the last 12 carry a distance. Splitting the READINGS
    // would compare swings 13-18 against 19-24 and call it front vs back —
    // a fabricated comparison between two stretches of the same nine.
    const swings = Array.from({ length: 24 }, (_, i) =>
      swing(i + 1, i >= 12 ? { distance_yd: 200 } : {}),
    );
    const facts = buildFacts(session(swings));
    expect(facts.splits.map((s) => s.metric)).not.toContain("distance_yd");
  });
});

describe("caveats name what actually went wrong", () => {
  test("a slow sample rate is disclosed, because it coarsens tempo", () => {
    const facts = buildFacts(
      session(series(4, "tempo_ratio", () => 3), { sample_rate_hz: 62 }),
    );
    expect(facts.caveats.join(" ")).toContain("62 Hz");
  });

  test("100 Hz passes without comment", () => {
    const facts = buildFacts(session(series(4, "tempo_ratio", () => 3)));
    expect(facts.caveats.join(" ")).not.toContain("Hz");
  });

  test("partial tempo coverage is stated rather than averaged over quietly", () => {
    const swings = Array.from({ length: 10 }, (_, i) =>
      swing(i + 1, i < 3 ? { tempo_ratio: 3 } : {}),
    );
    const caveats = buildFacts(session(swings)).caveats.join(" ");
    expect(caveats).toContain("3 of 10");
  });

  test("long waits are counted, not dropped", () => {
    // A five-minute tee wait between two drives used to delete both shots.
    const swings = [
      swing(1, { distance_yd: 250 }),
      swing(2, { distance_yd: 251, long_wait: true }),
      swing(3, { distance_yd: 249 }),
    ];
    const facts = buildFacts(session(swings));
    expect(facts.longWaits).toBe(1);
    expect(facts.fullShots!.n).toBe(3);
    expect(facts.caveats.join(" ")).toContain("long stop");
  });

  test("no distances at all is explained rather than left blank", () => {
    const facts = buildFacts(session(series(5, "peak_g", () => 4)));
    expect(facts.caveats.join(" ")).toContain("two");
  });
});

describe("the WHOOP join", () => {
  const round: GolfRound = {
    workoutId: "w1",
    date: "2026-08-18",
    start: "2026-08-18T13:00:00Z",
    end: "2026-08-18T17:00:00Z",
    durationMin: 240,
    strain: 11.2,
    avgHr: 96,
    maxHr: 141,
    recovery: { score: 42, restingHr: 58, hrvMs: 31 },
    sleep: { performancePct: 71, hoursAsleep: 5.4 },
    dayStrain: 14.1,
  };

  test("maps the physiology the coach is allowed to cite", () => {
    const facts = buildFacts(session(series(4, "peak_g", () => 4)), round);
    expect(facts.whoop).toEqual({
      recoveryPct: 42,
      hrvMs: 31,
      restingHr: 58,
      sleepHours: 5.4,
      sleepPerformancePct: 71,
      roundStrain: 11.2,
      dayStrain: 14.1,
      avgHr: 96,
      maxHr: 141,
    });
  });

  test("is null with no strap, so the prompt can forbid speculating", () => {
    expect(buildFacts(session(series(4, "peak_g", () => 4))).whoop).toBeNull();
  });

  test("missing sub-scores become null, never zero", () => {
    // A recovery of 0 and a recovery that was not scored are different facts,
    // and the second must not read as catastrophic.
    const bare: GolfRound = { ...round, recovery: undefined, sleep: undefined };
    const facts = buildFacts(session(series(4, "peak_g", () => 4)), bare);
    expect(facts.whoop!.recoveryPct).toBeNull();
    expect(facts.whoop!.sleepHours).toBeNull();
  });
});

describe("session shape", () => {
  test("the date comes from the first swing's local timestamp", () => {
    expect(buildFacts(session([swing(1)])).date).toBe("2026-08-18");
  });

  test("duration spans the round, and survives out-of-order swings", () => {
    const swings = [
      swing(1, { timestamp: "2026-08-18T13:30:00-04:00" }),
      swing(2, { timestamp: "2026-08-18T09:00:00-04:00" }),
    ];
    expect(buildFacts(session(swings)).durationMin).toBe(270);
  });

  test("a single swing has no measurable duration rather than a zero", () => {
    expect(buildFacts(session([swing(1)])).durationMin).toBeNull();
  });
});

describe("rendering", () => {
  const read: CoachRead = {
    headline: "Tempo held together; contact faded over the last six holes.",
    physiology: "Recovery of 42% is consistent with the fade, not proof of it.",
    findings: [
      {
        observation: "Impact force dropped 20% across the round.",
        evidence: "peak_g 100 → 80 over 6 swings a side.",
        confidence: "medium",
      },
    ],
    workOn: { focus: "Late-round contact.", drill: "Nine holes, ball first." },
    dataQuality: null,
  };

  test("leads with the round and the headline", () => {
    const facts = buildFacts(session(series(4, "tempo_ratio", () => 3.1)));
    const out = formatCoachRead(read, facts);
    expect(out).toContain("Round of 2026-08-18");
    expect(out).toContain(read.headline);
    expect(out).toContain("tempo 3.10:1");
  });

  test("omits the physiology and trust sections when there is nothing to say", () => {
    const facts = buildFacts(session(series(4, "peak_g", () => 4)));
    const out = formatCoachRead({ ...read, physiology: null }, facts);
    expect(out).not.toContain("Body");
    expect(out).not.toContain("Trust");
  });

  test("never prints a yardage line for a round whose distances were withheld", () => {
    const facts = buildFacts(
      session(series(10, "distance_yd", () => 200), {
        gps_warning: "GPS looks like your PHONE",
      }),
    );
    expect(formatCoachRead(read, facts)).not.toContain("longest");
  });
});

describe("error messages say what to do", () => {
  const KEYS = ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN"] as const;

  function withEnv<T>(values: Partial<Record<string, string>>, fn: () => T): T {
    const saved = KEYS.map((k) => [k, process.env[k]] as const);
    for (const k of KEYS) delete process.env[k];
    Object.assign(process.env, values);
    try {
      return fn();
    } finally {
      for (const k of KEYS) delete process.env[k];
      for (const [k, v] of saved) if (v !== undefined) process.env[k] = v;
    }
  }

  test("a local failure with no credentials explains how to get one", () => {
    // The SDK raises auth-resolution failure as a bare Error with no class to
    // match on, so this is the fallthrough branch — and it is by far the most
    // common way this command fails on a machine that has never run it.
    const out = withEnv({}, () =>
      explainError(new Error("Could not resolve authentication method.")),
    );
    expect(out).toContain("ANTHROPIC_API_KEY");
    expect(out).toContain("ant auth login");
  });

  test("and still shows the original cause rather than replacing it", () => {
    const out = withEnv({}, () => explainError(new Error("some other failure")));
    expect(out).toContain("some other failure");
  });

  test("says nothing about credentials when a key is already set", () => {
    const out = withEnv({ ANTHROPIC_API_KEY: "sk-test" }, () =>
      explainError(new Error("some other failure")),
    );
    expect(out).toBe("some other failure");
  });

  test("a non-Error value does not crash the handler", () => {
    expect(withEnv({ ANTHROPIC_API_KEY: "sk-test" }, () => explainError("nope"))).toBe(
      "nope",
    );
  });
});
