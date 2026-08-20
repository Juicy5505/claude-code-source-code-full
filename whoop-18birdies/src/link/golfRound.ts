import type {
  WhoopCycle,
  WhoopRecovery,
  WhoopSleep,
  WhoopSnapshot,
  WhoopWorkout,
} from "../whoop/types.ts";
import { whoopLocalDate } from "./correlate.ts";

/**
 * A golf round as WHOOP alone knows it.
 *
 * This is the WHOOP-only path: no watch, no phone strapped to an arm, no swing
 * detection. You wear the strap, you play, and WHOOP's own activity detection
 * logs the round. Everything here comes from WHOOP's cloud data.
 *
 * What that genuinely covers — the whole physiological side of a round — and
 * what it cannot cover, are both spelled out in `unavailable` below rather than
 * left for someone to discover. WHOOP has no accelerometer stream exposed to
 * any client, so swing count, tempo and shot distance are not "not implemented
 * yet"; they are outside what the device gives anyone.
 */
export interface GolfRound {
  workoutId: string;
  date: string;
  start: string;
  end: string;
  durationMin: number;
  sport?: string;
  strain?: number;
  avgHr?: number;
  maxHr?: number;
  kilojoule?: number;
  kcal?: number;
  distanceMeter?: number;
  distanceMiles?: number;
  zoneDurations?: Record<string, number>;
  /** Recovery reported the morning of the round. */
  recovery?: {
    score?: number;
    restingHr?: number;
    hrvMs?: number;
  };
  /** Sleep the night before. */
  sleep?: {
    performancePct?: number;
    hoursInBed?: number;
    hoursAsleep?: number;
    disturbances?: number;
  };
  /** Day strain for the whole cycle the round sits in. */
  dayStrain?: number;
}

/**
 * WHOOP labels activities by name; the numeric sport ids are not published in a
 * form worth hard-coding, and have changed. Matching on the name is both more
 * robust and inspectable — and `wb golf --list` prints every sport name in your
 * data so a mislabelled round is diagnosable rather than mysterious.
 */
export function isGolf(workout: WhoopWorkout): boolean {
  return (workout.sport_name ?? "").toLowerCase().includes("golf");
}

const HOUR_MS = 3_600_000;

function hours(milli: number | undefined): number | undefined {
  if (typeof milli !== "number" || !Number.isFinite(milli)) return undefined;
  return Math.round((milli / HOUR_MS) * 100) / 100;
}

function round1(value: number | undefined): number | undefined {
  if (typeof value !== "number" || !Number.isFinite(value)) return undefined;
  return Math.round(value * 10) / 10;
}

/** Every distinct sport name present, with counts. For diagnosing a miss. */
export function sportNames(snapshot: WhoopSnapshot): Array<{ sport: string; count: number }> {
  const counts = new Map<string, number>();
  for (const workout of snapshot.workouts) {
    const name = workout.sport_name ?? "(unnamed)";
    counts.set(name, (counts.get(name) ?? 0) + 1);
  }
  return [...counts.entries()]
    .map(([sport, count]) => ({ sport, count }))
    .sort((a, b) => b.count - a.count || a.sport.localeCompare(b.sport));
}

export function golfWorkouts(snapshot: WhoopSnapshot): WhoopWorkout[] {
  return snapshot.workouts
    .filter(isGolf)
    .slice()
    .sort((a, b) => b.start.localeCompare(a.start));
}

/**
 * Joins a workout to the physiology around it.
 *
 * The join is on LOCAL calendar date via WHOOP's own `timezone_offset`, not on
 * the UTC instant. An evening round is the next day in UTC, and joining on that
 * would pair it with the wrong night's sleep — which is precisely the number
 * you would be reading the report to find out about.
 */
export function buildGolfRound(
  snapshot: WhoopSnapshot,
  workout: WhoopWorkout,
): GolfRound {
  const date = whoopLocalDate(workout.start, workout.timezone_offset);
  const score = workout.score_state === "SCORED" ? workout.score : undefined;

  const startMs = Date.parse(workout.start);
  const endMs = Date.parse(workout.end);
  const durationMin =
    Number.isFinite(startMs) && Number.isFinite(endMs) && endMs > startMs
      ? Math.round((endMs - startMs) / 60_000)
      : 0;

  const cycle: WhoopCycle | undefined = snapshot.cycles.find(
    (c) => whoopLocalDate(c.start, c.timezone_offset) === date,
  );
  const recovery: WhoopRecovery | undefined = cycle
    ? snapshot.recoveries.find((r) => r.cycle_id === cycle.id)
    : undefined;
  // Sleep that ENDED on the round's date is the night before it — a sleep that
  // started on that date is the night after, and would flatter or damn the
  // round with physiology it could not have influenced.
  const sleep: WhoopSleep | undefined = snapshot.sleeps.find(
    (s) => !s.nap && whoopLocalDate(s.end, s.timezone_offset) === date,
  );

  const recoveryScore = recovery?.score_state === "SCORED" ? recovery.score : undefined;
  const sleepScore = sleep?.score_state === "SCORED" ? sleep.score : undefined;
  const stages = sleepScore?.stage_summary;

  const inBed = stages?.total_in_bed_time_milli;
  const awake = stages?.total_awake_time_milli;
  const asleep =
    typeof inBed === "number" && typeof awake === "number" ? inBed - awake : undefined;

  return {
    workoutId: workout.id,
    date,
    start: workout.start,
    end: workout.end,
    durationMin,
    sport: workout.sport_name,
    strain: round1(score?.strain),
    avgHr: score?.average_heart_rate,
    maxHr: score?.max_heart_rate,
    kilojoule: score?.kilojoule === undefined ? undefined : Math.round(score.kilojoule),
    // WHOOP reports energy in kilojoules; dietary Calories are kJ / 4.184.
    kcal:
      score?.kilojoule === undefined ? undefined : Math.round(score.kilojoule / 4.184),
    distanceMeter: score?.distance_meter,
    distanceMiles:
      score?.distance_meter === undefined
        ? undefined
        : Math.round((score.distance_meter / 1609.344) * 100) / 100,
    zoneDurations: score?.zone_durations,
    recovery: recoveryScore
      ? {
          score: recoveryScore.recovery_score,
          restingHr: recoveryScore.resting_heart_rate,
          hrvMs: round1(recoveryScore.hrv_rmssd_milli),
        }
      : undefined,
    sleep: sleepScore
      ? {
          performancePct: sleepScore.sleep_performance_percentage,
          hoursInBed: hours(inBed),
          hoursAsleep: hours(asleep),
          disturbances: stages?.disturbance_count,
        }
      : undefined,
    dayStrain:
      cycle?.score_state === "SCORED" ? round1(cycle.score?.strain) : undefined,
  };
}

function zoneLabel(key: string): string {
  // WHOOP's zone keys arrive as e.g. "zone_zero_milli". Rendering whatever keys
  // come back, rather than assuming a fixed set, means a schema change degrades
  // to an odd label instead of silently dropping a zone.
  const cleaned = key.replace(/_milli$/, "").replace(/^zone_/, "").replace(/_/g, " ");
  const words: Record<string, string> = {
    zero: "Zone 0  (<50%)",
    one: "Zone 1  (50-60%)",
    two: "Zone 2  (60-70%)",
    three: "Zone 3  (70-80%)",
    four: "Zone 4  (80-90%)",
    five: "Zone 5  (90%+)",
  };
  return words[cleaned] ?? cleaned;
}

function bar(fraction: number, width = 24): string {
  const filled = Math.max(0, Math.min(width, Math.round(fraction * width)));
  return "#".repeat(filled) + ".".repeat(width - filled);
}

export function formatGolfRound(round: GolfRound): string {
  const lines: string[] = [];
  const hoursPart = Math.floor(round.durationMin / 60);
  const minsPart = round.durationMin % 60;
  const duration = hoursPart ? `${hoursPart}h ${minsPart}m` : `${minsPart}m`;

  lines.push(`Golf round — ${round.date}`);
  lines.push("=".repeat(40));
  lines.push(`  ${round.sport ?? "workout"} · ${duration}`);
  lines.push("");

  lines.push("During the round");
  if (round.strain !== undefined) lines.push(`  Strain            ${round.strain}`);
  if (round.avgHr !== undefined) lines.push(`  Average HR        ${round.avgHr} bpm`);
  if (round.maxHr !== undefined) lines.push(`  Max HR            ${round.maxHr} bpm`);
  if (round.kcal !== undefined) lines.push(`  Energy            ${round.kcal} kcal`);
  if (round.distanceMiles !== undefined) {
    lines.push(`  Distance walked   ${round.distanceMiles} mi`);
  }
  if (round.strain === undefined && round.avgHr === undefined) {
    lines.push("  (not scored yet — WHOOP scores an activity a while after it ends)");
  }

  const zones = round.zoneDurations;
  if (zones && Object.keys(zones).length) {
    const total = Object.values(zones).reduce((sum, v) => sum + (v || 0), 0);
    if (total > 0) {
      lines.push("");
      lines.push("Heart-rate zones");
      for (const [key, milli] of Object.entries(zones)) {
        const minutes = Math.round((milli || 0) / 60_000);
        const share = (milli || 0) / total;
        lines.push(
          `  ${zoneLabel(key).padEnd(18)} ${bar(share)} ${String(minutes).padStart(3)} min`,
        );
      }
    }
  }

  if (round.recovery || round.sleep || round.dayStrain !== undefined) {
    lines.push("");
    lines.push("Body going in");
    if (round.recovery?.score !== undefined) {
      lines.push(`  Recovery          ${round.recovery.score}%`);
    }
    if (round.recovery?.restingHr !== undefined) {
      lines.push(`  Resting HR        ${round.recovery.restingHr} bpm`);
    }
    if (round.recovery?.hrvMs !== undefined) {
      lines.push(`  HRV               ${round.recovery.hrvMs} ms`);
    }
    if (round.sleep?.hoursAsleep !== undefined) {
      lines.push(`  Slept             ${round.sleep.hoursAsleep} h`);
    }
    if (round.sleep?.performancePct !== undefined) {
      lines.push(`  Sleep performance ${round.sleep.performancePct}%`);
    }
    if (round.dayStrain !== undefined) {
      lines.push(`  Day strain        ${round.dayStrain}`);
    }
  }

  lines.push("");
  lines.push("What WHOOP cannot tell you about this round");
  lines.push("  Swing count, tempo, shot distance, club, score.");
  lines.push("  The strap exposes no motion data to any client — only heart rate —");
  lines.push("  so these need either a phone/watch sensor or your own scorecard.");
  lines.push("  Add the score with:  wb import-csv, or POST to `wb serve`.");

  return lines.join("\n");
}

/**
 * What WHOOP genuinely covers, and what it does not. Kept as data so the CLI
 * and the docs cannot drift apart from each other.
 */
export const whoopCoverage = {
  covered: [
    "the round happened, and exactly when it started and ended",
    "strain for the round, and for the whole day",
    "average and max heart rate, and time in each HR zone",
    "energy burned",
    "distance walked, when WHOOP records it",
    "recovery, resting HR and HRV that morning",
    "sleep the night before",
  ],
  unavailable: [
    "swing count — needs an accelerometer stream WHOOP exposes to nobody",
    "tempo — same reason",
    "shot distance — needs per-shot GPS, which the strap has no radio for",
    "club, score, putts — WHOOP has no concept of them and no write API",
  ],
} as const;
