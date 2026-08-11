import { describe, expect, test } from "bun:test";
import {
  correlateAll,
  indexPhysiology,
  linkRounds,
  previousDate,
  sleepHours,
  summarise,
  whoopLocalDate,
} from "../src/link/correlate.ts";
import { computeReadiness, sleepUtility, strainUtility } from "../src/link/readiness.ts";
import type { Round } from "../src/rounds/types.ts";
import type { WhoopSleep, WhoopSnapshot } from "../src/whoop/types.ts";

const HOUR = 3_600_000;

function sleep(id: string, start: string, asleepHours: number, awakeHours = 0.5): WhoopSleep {
  return {
    id,
    start,
    end: start,
    timezone_offset: "-07:00",
    nap: false,
    score_state: "SCORED",
    score: {
      sleep_performance_percentage: 85,
      stage_summary: {
        total_in_bed_time_milli: (asleepHours + awakeHours) * HOUR,
        total_awake_time_milli: awakeHours * HOUR,
        total_light_sleep_time_milli: 0,
        total_slow_wave_sleep_time_milli: 0,
        total_rem_sleep_time_milli: 0,
        sleep_cycle_count: 4,
        disturbance_count: 3,
      },
    },
  };
}

/** Builds a snapshot where recovery on day i is `recoveries[i]`. */
function buildSnapshot(days: { date: string; recovery: number; strain: number; asleep: number }[]): WhoopSnapshot {
  const snap: WhoopSnapshot = {
    fetchedAt: new Date().toISOString(),
    cycles: [],
    recoveries: [],
    sleeps: [],
    workouts: [],
  };
  days.forEach((d, i) => {
    const cycleId = `c${i}`;
    const sleepId = `s${i}`;
    snap.cycles.push({
      id: cycleId,
      start: `${d.date}T13:00:00.000Z`, // 06:00 local at -07:00
      end: null,
      timezone_offset: "-07:00",
      score_state: "SCORED",
      score: { strain: d.strain, kilojoule: 8000, average_heart_rate: 70, max_heart_rate: 150 },
    });
    snap.sleeps.push(sleep(sleepId, `${d.date}T08:00:00.000Z`, d.asleep));
    snap.recoveries.push({
      cycle_id: cycleId,
      sleep_id: sleepId,
      score_state: "SCORED",
      score: { recovery_score: d.recovery, resting_heart_rate: 55, hrv_rmssd_milli: 60 },
    });
  });
  return snap;
}

describe("whoop date alignment", () => {
  test("applies the timezone offset instead of using UTC", () => {
    // 2026-05-05T04:00Z is 2026-05-04 21:00 in Pacific — still the 4th locally.
    expect(whoopLocalDate("2026-05-05T04:00:00.000Z", "-07:00")).toBe("2026-05-04");
  });

  test("handles positive offsets that push into the next day", () => {
    expect(whoopLocalDate("2026-05-04T23:00:00.000Z", "+05:30")).toBe("2026-05-05");
  });

  test("falls back to the UTC date on a malformed offset", () => {
    expect(whoopLocalDate("2026-05-04T23:00:00.000Z", "garbage")).toBe("2026-05-04");
  });

  test("previousDate crosses a month boundary", () => {
    expect(previousDate("2026-05-01")).toBe("2026-04-30");
  });
});

describe("sleep and strain utilities", () => {
  test("sleepHours subtracts awake time from in-bed time", () => {
    expect(sleepHours(sleep("s", "2026-05-04T08:00:00.000Z", 7, 0.5))).toBeCloseTo(7, 6);
  });

  test("sleepHours is null when the record is unscored", () => {
    const unscored: WhoopSleep = {
      id: "s",
      start: "2026-05-04T08:00:00.000Z",
      end: "2026-05-04T15:00:00.000Z",
      timezone_offset: "-07:00",
      nap: false,
      score_state: "PENDING_SCORE",
    };
    expect(sleepHours(unscored)).toBeNull();
  });

  test("sleep utility saturates at 8 hours and floors at 4", () => {
    expect(sleepUtility(3)).toBe(0);
    expect(sleepUtility(6)).toBe(50);
    expect(sleepUtility(9)).toBe(100);
  });

  test("strain utility inverts the 0-21 WHOOP scale", () => {
    expect(strainUtility(0)).toBe(100);
    expect(strainUtility(21)).toBe(0);
    expect(strainUtility(30)).toBe(0);
  });
});

describe("physiology index", () => {
  const snapshot = buildSnapshot([
    { date: "2026-05-03", recovery: 40, strain: 16, asleep: 6 },
    { date: "2026-05-04", recovery: 80, strain: 10, asleep: 8 },
  ]);

  test("indexes recovery, sleep and strain by local date", () => {
    const idx = indexPhysiology(snapshot);
    const day = idx.get("2026-05-04")!;
    expect(day.recoveryScore).toBe(80);
    expect(day.sleepHours).toBeCloseTo(8, 6);
    expect(day.dayStrain).toBe(10);
  });

  test("carries the prior day's strain forward", () => {
    const idx = indexPhysiology(snapshot);
    expect(idx.get("2026-05-04")!.priorDayStrain).toBe(16);
    // Nothing precedes the first day in the window.
    expect(idx.get("2026-05-03")!.priorDayStrain).toBeUndefined();
  });

  test("ignores unscored recoveries", () => {
    const snap = buildSnapshot([{ date: "2026-05-04", recovery: 80, strain: 10, asleep: 8 }]);
    snap.recoveries[0]!.score_state = "PENDING_SCORE";
    expect(indexPhysiology(snap).get("2026-05-04")!.recoveryScore).toBeUndefined();
  });
});

describe("linking and correlation", () => {
  // Recovery rises across the window while strokes-to-par falls: a clean
  // negative relationship the correlation must recover.
  const days = [
    { date: "2026-05-01", recovery: 30, strain: 12, asleep: 5 },
    { date: "2026-05-02", recovery: 45, strain: 12, asleep: 6 },
    { date: "2026-05-03", recovery: 60, strain: 12, asleep: 7 },
    { date: "2026-05-04", recovery: 75, strain: 12, asleep: 8 },
    { date: "2026-05-05", recovery: 90, strain: 12, asleep: 9 },
  ];
  const snapshot = buildSnapshot(days);
  const rounds: Round[] = days.map((d, i) => ({
    id: `r${i}`,
    date: d.date,
    holes: 18,
    par: 72,
    score: 92 - i * 2,
    source: "csv",
  }));

  test("attaches physiology to each round", () => {
    const linked = linkRounds(rounds, snapshot);
    expect(linked).toHaveLength(5);
    expect(linked[0]!.physiology?.recoveryScore).toBe(30);
    expect(linked[0]!.scoreToPar).toBe(20);
  });

  test("leaves physiology null for a round outside the WHOOP window", () => {
    const orphan: Round = { id: "o", date: "2020-01-01", holes: 18, source: "csv" };
    expect(linkRounds([orphan], snapshot)[0]!.physiology).toBeNull();
  });

  test("recovers the negative recovery-to-score relationship", () => {
    const correlations = correlateAll(linkRounds(rounds, snapshot));
    const recovery = correlations.find((c) => c.key === "recoveryScore")!;
    expect(recovery.n).toBe(5);
    expect(recovery.pearson).toBeCloseTo(-1, 10);
  });

  test("drops metrics with fewer than three usable rounds", () => {
    const correlations = correlateAll(linkRounds(rounds.slice(0, 2), snapshot));
    expect(correlations).toHaveLength(0);
  });

  test("summary counts rounds by what they can contribute", () => {
    const noScore: Round = { id: "n", date: "2026-05-04", holes: 18, source: "apple-health" };
    const summary = summarise(linkRounds([...rounds, noScore], snapshot));
    expect(summary.totalRounds).toBe(6);
    expect(summary.roundsWithScore).toBe(5);
    expect(summary.roundsWithPhysiology).toBe(6);
    expect(summary.usableRounds).toBe(5);
  });
});

describe("readiness", () => {
  test("scores a rested day high and a depleted day low", () => {
    const rested = computeReadiness({
      date: "2026-05-04",
      recoveryScore: 92,
      sleepHours: 8.2,
      priorDayStrain: 6,
    });
    const wrecked = computeReadiness({
      date: "2026-05-04",
      recoveryScore: 22,
      sleepHours: 4.5,
      priorDayStrain: 18,
    });
    expect(rested.score).toBeGreaterThan(wrecked.score);
    expect(rested.verdict).toBe("prime");
    expect(wrecked.verdict).toBe("compromised");
  });

  test("renormalises weights when an input is missing", () => {
    const only = computeReadiness({ date: "2026-05-04", recoveryScore: 80 });
    expect(only.components).toHaveLength(1);
    // A single present component should carry the full score, not 50% of it.
    expect(only.score).toBeCloseTo(80, 6);
  });

  test("reports missing data rather than inventing a score", () => {
    const none = computeReadiness({ date: "2026-05-04" });
    expect(Number.isNaN(none.score)).toBe(true);
    expect(none.advice[0]).toMatch(/no whoop data/i);
  });

  test("stays on default weights until there are enough rounds", () => {
    const r = computeReadiness({ date: "2026-05-04", recoveryScore: 80 }, [
      {
        key: "recoveryScore",
        label: "Recovery %",
        unit: "%",
        n: 4,
        pearson: -0.9,
        spearman: -0.9,
        pValue: 0.01,
        metricMean: 60,
        scoreMean: 12,
      },
    ]);
    expect(r.personalised).toBe(false);
  });

  test("personalises weights once enough rounds exist", () => {
    const r = computeReadiness(
      { date: "2026-05-04", recoveryScore: 80, sleepHours: 7, priorDayStrain: 10 },
      [
        {
          key: "recoveryScore",
          label: "Recovery %",
          unit: "%",
          n: 12,
          pearson: -0.8,
          spearman: -0.8,
          pValue: 0.002,
          metricMean: 60,
          scoreMean: 12,
        },
      ],
    );
    expect(r.personalised).toBe(true);
    const recovery = r.components.find((c) => c.label === "Recovery")!;
    // Recovery correlates, so it should outweigh its 0.5 default share.
    expect(recovery.weight).toBeGreaterThan(0.5);
    expect(r.components.reduce((a, c) => a + c.weight, 0)).toBeCloseTo(1, 10);
  });

  test("flags short sleep in the advice", () => {
    const r = computeReadiness({ date: "2026-05-04", recoveryScore: 50, sleepHours: 5 });
    expect(r.advice.some((a) => /sleep/i.test(a))).toBe(true);
  });
});
