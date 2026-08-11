import { createReadStream } from "node:fs";
import { type Round, roundId } from "./types.ts";

/**
 * Parser for the `export.xml` inside an Apple Health export
 * (Health app -> profile -> Export All Health Data).
 *
 * The file is routinely hundreds of megabytes, so this scans a stream with a
 * sliding buffer rather than reading it whole.
 */

export interface AppleWorkout {
  activityType: string;
  sourceName: string;
  startDate: string;
  endDate: string;
  durationMinutes: number | null;
  distanceKm: number | null;
}

/**
 * Apple writes dates as `2026-05-04 08:10:00 -0700`, which `Date.parse` does
 * not reliably accept. Rewrite into ISO 8601 before parsing.
 */
export function parseAppleDate(value: string): Date | null {
  const m = /^(\d{4}-\d{2}-\d{2}) (\d{2}:\d{2}:\d{2}) ([+-]\d{2})(\d{2})$/.exec(
    value.trim(),
  );
  if (!m) {
    const fallback = Date.parse(value);
    return Number.isFinite(fallback) ? new Date(fallback) : null;
  }
  const [, date, time, tzHour, tzMin] = m;
  const parsed = Date.parse(`${date}T${time}${tzHour}:${tzMin}`);
  return Number.isFinite(parsed) ? new Date(parsed) : null;
}

/**
 * The local calendar date the round was played, taken from the offset embedded
 * in the Apple timestamp. Using UTC here would push early-morning tee times in
 * western timezones onto the previous day and break the join with WHOOP.
 */
export function localDateOf(value: string): string | null {
  const m = /^(\d{4}-\d{2}-\d{2}) /.exec(value.trim());
  if (m) return m[1]!;
  const d = parseAppleDate(value);
  return d ? d.toISOString().slice(0, 10) : null;
}

function attr(tag: string, name: string): string | undefined {
  const m = new RegExp(`\\s${name}="([^"]*)"`).exec(tag);
  return m?.[1];
}

function toRound(w: AppleWorkout): Round | null {
  const date = localDateOf(w.startDate);
  if (!date) return null;

  // Apple has no notion of holes; infer from elapsed time. A 9-hole round runs
  // roughly 2 - 2.5 hours and 18 roughly 4 - 5, so 3 hours splits them well.
  const holes = w.durationMinutes != null && w.durationMinutes < 180 ? 9 : 18;
  const course = w.sourceName || undefined;
  const start = parseAppleDate(w.startDate);
  const end = parseAppleDate(w.endDate);

  return {
    id: roundId(date, course, holes),
    date,
    course,
    holes,
    startedAt: start?.toISOString(),
    endedAt: end?.toISOString(),
    source: "apple-health",
    notes: `Apple Health ${w.activityType}${
      w.distanceKm != null ? ` · ${w.distanceKm.toFixed(1)} km walked` : ""
    } (no score — Apple Health carries no scorecard)`,
  };
}

export interface ExtractOptions {
  /**
   * Extra source-app names to treat as golf. 18Birdies does not classify its
   * activity as an HKWorkoutActivityTypeGolf workout, so matching on the
   * activity type alone misses rounds it recorded.
   */
  sourceMatches?: string[];
}

const GOLF_TYPE = "HKWorkoutActivityTypeGolf";
const DEFAULT_SOURCES = ["18birdies", "18 birdies"];

export function workoutMatches(
  w: AppleWorkout,
  opts: ExtractOptions = {},
): boolean {
  if (w.activityType === GOLF_TYPE) return true;
  const needles = [
    ...DEFAULT_SOURCES,
    ...(opts.sourceMatches ?? []).map((s) => s.toLowerCase()),
  ];
  const source = w.sourceName.toLowerCase();
  return needles.some((n) => source.includes(n));
}

export function workoutFromTag(tag: string): AppleWorkout | null {
  const activityType = attr(tag, "workoutActivityType");
  const startDate = attr(tag, "startDate");
  const endDate = attr(tag, "endDate");
  if (!activityType || !startDate || !endDate) return null;

  const duration = Number(attr(tag, "duration"));
  const durationUnit = attr(tag, "durationUnit") ?? "min";
  const durationMinutes = Number.isFinite(duration)
    ? durationUnit === "sec"
      ? duration / 60
      : duration
    : null;

  const distance = Number(attr(tag, "totalDistance"));
  const distanceUnit = attr(tag, "totalDistanceUnit") ?? "km";
  const distanceKm = Number.isFinite(distance)
    ? distanceUnit === "mi"
      ? distance * 1.609_344
      : distance
    : null;

  return {
    activityType,
    sourceName: attr(tag, "sourceName") ?? "",
    startDate,
    endDate,
    durationMinutes,
    distanceKm,
  };
}

/** Pulls every `<Workout ...>` opening tag out of a chunk of XML text. */
export function scanWorkoutTags(text: string): string[] {
  return text.match(/<Workout\s[^>]*>/g) ?? [];
}

export async function roundsFromAppleHealthExport(
  filePath: string,
  opts: ExtractOptions = {},
): Promise<Round[]> {
  const workouts: AppleWorkout[] = [];
  let buffer = "";

  await new Promise<void>((resolve, reject) => {
    const stream = createReadStream(filePath, { encoding: "utf8" });
    stream.on("data", (chunk) => {
      buffer += chunk;
      for (const tag of scanWorkoutTags(buffer)) {
        const w = workoutFromTag(tag);
        if (w) workouts.push(w);
      }
      // Keep only the tail, which may hold a tag split across the chunk
      // boundary. Workout tags are well under 4 KB in practice.
      const lastClose = buffer.lastIndexOf(">");
      buffer = lastClose === -1 ? buffer.slice(-4096) : buffer.slice(lastClose + 1);
    });
    stream.on("error", reject);
    stream.on("end", () => resolve());
  });

  const rounds: Round[] = [];
  for (const w of workouts) {
    if (!workoutMatches(w, opts)) continue;
    const round = toRound(w);
    if (round) rounds.push(round);
  }
  return rounds;
}
