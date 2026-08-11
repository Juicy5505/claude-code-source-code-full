import { type Round, scoreToPar } from "../rounds/types.ts";
import type { WhoopSleep, WhoopSnapshot } from "../whoop/types.ts";
import { type CorrelationResult, correlate, mean } from "./stats.ts";

/**
 * Local calendar date for a WHOOP timestamp. WHOOP returns UTC instants plus a
 * separate `timezone_offset` like `-07:00`; without applying it, a cycle that
 * starts late evening in California lands on the next UTC day and would be
 * joined to the wrong round.
 */
export function whoopLocalDate(iso: string, offset: string): string {
  const base = Date.parse(iso);
  if (!Number.isFinite(base)) return iso.slice(0, 10);
  const m = /^([+-])(\d{2}):?(\d{2})$/.exec(offset.trim());
  if (!m) return new Date(base).toISOString().slice(0, 10);
  const sign = m[1] === "-" ? -1 : 1;
  const shiftMs = sign * (Number(m[2]) * 60 + Number(m[3])) * 60_000;
  return new Date(base + shiftMs).toISOString().slice(0, 10);
}

export function previousDate(date: string): string {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() - 1);
  return d.toISOString().slice(0, 10);
}

/** Actual asleep time, i.e. in-bed minus awake. */
export function sleepHours(sleep: WhoopSleep): number | null {
  const stages = sleep.score?.stage_summary;
  if (!stages) return null;
  const ms = stages.total_in_bed_time_milli - stages.total_awake_time_milli;
  return ms > 0 ? ms / 3_600_000 : null;
}

/** WHOOP physiology aligned to the day of a round. */
export interface DayPhysiology {
  date: string;
  recoveryScore?: number;
  hrvMs?: number;
  restingHeartRate?: number;
  sleepHours?: number;
  sleepPerformance?: number;
  dayStrain?: number;
  priorDayStrain?: number;
}

export function indexPhysiology(snapshot: WhoopSnapshot): Map<string, DayPhysiology> {
  const byDate = new Map<string, DayPhysiology>();
  const get = (date: string): DayPhysiology => {
    let d = byDate.get(date);
    if (!d) {
      d = { date };
      byDate.set(date, d);
    }
    return d;
  };

  const cycleDate = new Map<string, string>();
  for (const cycle of snapshot.cycles) {
    const date = whoopLocalDate(cycle.start, cycle.timezone_offset);
    cycleDate.set(cycle.id, date);
    if (cycle.score_state === "SCORED" && cycle.score) {
      get(date).dayStrain = cycle.score.strain;
    }
  }

  const sleepById = new Map(snapshot.sleeps.map((s) => [s.id, s]));

  for (const recovery of snapshot.recoveries) {
    const date = cycleDate.get(recovery.cycle_id);
    // A recovery whose cycle falls outside the fetched window has no date to
    // attach to; dropping it is correct, guessing one is not.
    if (!date) continue;
    const day = get(date);
    if (recovery.score_state === "SCORED" && recovery.score) {
      day.recoveryScore = recovery.score.recovery_score;
      day.hrvMs = recovery.score.hrv_rmssd_milli;
      day.restingHeartRate = recovery.score.resting_heart_rate;
    }
    const sleep = sleepById.get(recovery.sleep_id);
    if (sleep && sleep.score_state === "SCORED") {
      const hours = sleepHours(sleep);
      if (hours != null) day.sleepHours = hours;
      if (sleep.score?.sleep_performance_percentage != null) {
        day.sleepPerformance = sleep.score.sleep_performance_percentage;
      }
    }
  }

  for (const day of byDate.values()) {
    day.priorDayStrain = byDate.get(previousDate(day.date))?.dayStrain;
  }

  return byDate;
}

export interface LinkedRound {
  round: Round;
  physiology: DayPhysiology | null;
  scoreToPar: number | null;
}

export function linkRounds(
  rounds: Round[],
  snapshot: WhoopSnapshot,
): LinkedRound[] {
  const index = indexPhysiology(snapshot);
  return rounds.map((round) => ({
    round,
    physiology: index.get(round.date) ?? null,
    scoreToPar: scoreToPar(round),
  }));
}

/** The physiological inputs tested against scoring. */
export const METRICS = [
  { key: "recoveryScore", label: "Recovery %", unit: "%" },
  { key: "hrvMs", label: "HRV (RMSSD)", unit: "ms" },
  { key: "restingHeartRate", label: "Resting HR", unit: "bpm" },
  { key: "sleepHours", label: "Sleep duration", unit: "h" },
  { key: "sleepPerformance", label: "Sleep performance", unit: "%" },
  { key: "priorDayStrain", label: "Prior-day strain", unit: "" },
] as const;

export type MetricKey = (typeof METRICS)[number]["key"];

export interface MetricCorrelation extends CorrelationResult {
  key: MetricKey;
  label: string;
  unit: string;
  metricMean: number;
  /** Mean strokes-to-par among rounds included in this correlation. */
  scoreMean: number;
}

/**
 * Correlates each metric against strokes-to-par. A negative correlation means
 * more of the metric goes with a lower (better) score.
 */
export function correlateAll(linked: LinkedRound[]): MetricCorrelation[] {
  const out: MetricCorrelation[] = [];

  for (const metric of METRICS) {
    const xs: number[] = [];
    const ys: number[] = [];
    for (const item of linked) {
      const value = item.physiology?.[metric.key];
      if (value == null || item.scoreToPar == null) continue;
      xs.push(value);
      ys.push(item.scoreToPar);
    }
    if (xs.length < 3) continue;
    out.push({
      key: metric.key,
      label: metric.label,
      unit: metric.unit,
      metricMean: mean(xs),
      scoreMean: mean(ys),
      ...correlate(xs, ys),
    });
  }

  // Strongest relationships first, ignoring direction.
  return out.sort((a, b) => Math.abs(b.pearson) - Math.abs(a.pearson));
}

export interface LinkSummary {
  totalRounds: number;
  roundsWithPhysiology: number;
  roundsWithScore: number;
  usableRounds: number;
  correlations: MetricCorrelation[];
}

export function summarise(linked: LinkedRound[]): LinkSummary {
  return {
    totalRounds: linked.length,
    roundsWithPhysiology: linked.filter((l) => l.physiology != null).length,
    roundsWithScore: linked.filter((l) => l.scoreToPar != null).length,
    usableRounds: linked.filter((l) => l.physiology != null && l.scoreToPar != null)
      .length,
    correlations: correlateAll(linked),
  };
}
