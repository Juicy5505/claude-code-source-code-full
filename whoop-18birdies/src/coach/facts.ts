import type { GolfRound } from "../link/golfRound.ts";
import type { WatchSession } from "../store.ts";

/**
 * Turns a raw session into the small set of numbers a coach can reason about.
 *
 * WHY THIS EXISTS RATHER THAN SENDING THE SESSION STRAIGHT TO THE MODEL
 *
 * A round is eighty swings of nested JSON. Handing that over has three
 * failure modes, and the third is the one that matters:
 *
 *  1. It is most of a context window for data that compresses to twenty
 *     numbers.
 *  2. Arithmetic done token-by-token is arithmetic that can come out wrong,
 *     and a wrong average is indistinguishable from a right one in prose.
 *  3. Anything present in the input can be reasoned about — including numbers
 *     that should never be reasoned about at all. That is not hypothetical
 *     here: when `gps_warning` is set, every distance in the file is a
 *     measurement of where the CART went, and the only safe thing to do with
 *     those yardages is to not send them.
 *
 * So every statistic is computed here, in code, under test. The model receives
 * this object and nothing else, which makes "the coach invented a number" a
 * category of bug that cannot occur.
 */

/** A metric summarised over the swings that actually carried it. */
export interface Stat {
  /** How many swings contributed. Carried so small samples stay visible. */
  n: number;
  mean: number;
  median: number;
  min: number;
  max: number;
  /** Coefficient of variation — spread relative to size. Null under `MIN_CV_N`. */
  cv: number | null;
}

/** A first-half / second-half comparison, for fatigue. */
export interface Split {
  metric: string;
  firstHalf: number;
  secondHalf: number;
  changePct: number;
  /** Swings per half. Both halves cleared `MIN_SPLIT_N` or this is not emitted. */
  n: number;
}

export interface WhoopFacts {
  recoveryPct: number | null;
  hrvMs: number | null;
  restingHr: number | null;
  sleepHours: number | null;
  sleepPerformancePct: number | null;
  roundStrain: number | null;
  dayStrain: number | null;
  avgHr: number | null;
  maxHr: number | null;
}

export interface RoundFacts {
  date: string | null;
  mode: string;
  swingCount: number;
  durationMin: number | null;
  sampleRateHz: number | null;
  tempo: Stat | null;
  /** Full-swing yardages. Null when unmeasured OR withheld — see `distancesWithheld`. */
  fullShots: Stat | null;
  longestYd: number | null;
  /** Chips and putts, counted but never mixed into `fullShots`. */
  shortShots: number;
  peakG: Stat | null;
  splits: Split[];
  longWaits: number;
  /**
   * True when distances existed but were deliberately dropped because the
   * session says the GPS was not on the wrist. See `caveats` for the reason in
   * words; both are sent to the model.
   */
  distancesWithheld: boolean;
  /** Everything that should temper a conclusion, stated plainly. */
  caveats: string[];
  whoop: WhoopFacts | null;
}

/** Below this, a coefficient of variation is describing the sample, not the swing. */
export const MIN_CV_N = 4;

/**
 * Swings needed in EACH half before a front/back comparison is reported.
 *
 * Six is not a statistical claim, it is a floor against a specific bad output:
 * with three swings a side, one thin 7-iron moves the "second half" mean by
 * thirty yards and the coach confidently reports a fatigue decline that is one
 * bad contact. Below the floor the split is not emitted at all, so there is
 * nothing for the model to over-read.
 */
export const MIN_SPLIT_N = 6;

function numbersFrom(swings: Array<Record<string, unknown>>, key: string): number[] {
  const out: number[] = [];
  for (const swing of swings) {
    const value = swing[key];
    if (typeof value === "number" && Number.isFinite(value)) out.push(value);
  }
  return out;
}

function round(value: number, places: number): number {
  const scale = 10 ** places;
  return Math.round(value * scale) / scale;
}

function median(sorted: number[]): number {
  const mid = sorted.length >> 1;
  return sorted.length % 2 === 1
    ? sorted[mid]!
    : (sorted[mid - 1]! + sorted[mid]!) / 2;
}

export function summarise(values: number[], places = 2): Stat | null {
  if (values.length === 0) return null;
  const mean = values.reduce((a, b) => a + b, 0) / values.length;
  const sorted = [...values].sort((a, b) => a - b);

  // Sample standard deviation (n-1). The population form understates spread on
  // the small samples a round actually produces, which would make an erratic
  // day read as a consistent one.
  let cv: number | null = null;
  if (values.length >= MIN_CV_N && mean !== 0) {
    const variance =
      values.reduce((acc, v) => acc + (v - mean) ** 2, 0) / (values.length - 1);
    cv = round(Math.sqrt(variance) / Math.abs(mean), 3);
  }

  return {
    n: values.length,
    mean: round(mean, places),
    median: round(median(sorted), places),
    min: round(sorted[0]!, places),
    max: round(sorted[sorted.length - 1]!, places),
    cv,
  };
}

function splitOf(
  swings: Array<Record<string, unknown>>,
  key: string,
  metric: string,
  places: number,
): Split | null {
  // Split the SWINGS in half, then take each half's readings — not the readings
  // in half. Those differ whenever a metric is missing on some swings, and
  // splitting the readings would silently compare two different stretches of
  // the round against each other.
  const half = Math.floor(swings.length / 2);
  const first = numbersFrom(swings.slice(0, half), key);
  const second = numbersFrom(swings.slice(half), key);
  if (first.length < MIN_SPLIT_N || second.length < MIN_SPLIT_N) return null;

  const firstMean = first.reduce((a, b) => a + b, 0) / first.length;
  const secondMean = second.reduce((a, b) => a + b, 0) / second.length;
  if (firstMean === 0) return null;

  return {
    metric,
    firstHalf: round(firstMean, places),
    secondHalf: round(secondMean, places),
    changePct: round(((secondMean - firstMean) / Math.abs(firstMean)) * 100, 1),
    n: Math.min(first.length, second.length),
  };
}

function minutesBetween(swings: Array<Record<string, unknown>>): number | null {
  const stamps = swings
    .map((s) => (typeof s.timestamp === "string" ? Date.parse(s.timestamp) : NaN))
    .filter((t) => Number.isFinite(t));
  if (stamps.length < 2) return null;
  const span = Math.max(...stamps) - Math.min(...stamps);
  return span > 0 ? round(span / 60_000, 1) : null;
}

function whoopFactsFrom(round_: GolfRound): WhoopFacts {
  const num = (v: number | undefined): number | null =>
    typeof v === "number" && Number.isFinite(v) ? v : null;
  return {
    recoveryPct: num(round_.recovery?.score),
    hrvMs: num(round_.recovery?.hrvMs),
    restingHr: num(round_.recovery?.restingHr),
    sleepHours: num(round_.sleep?.hoursAsleep),
    sleepPerformancePct: num(round_.sleep?.performancePct),
    roundStrain: num(round_.strain),
    dayStrain: num(round_.dayStrain),
    avgHr: num(round_.avgHr),
    maxHr: num(round_.maxHr),
  };
}

/**
 * Build the fact sheet. `whoop` is optional: a range session, or a round played
 * without the strap, still produces a usable read on the swing itself.
 */
export function buildFacts(
  session: WatchSession,
  whoop?: GolfRound | null,
): RoundFacts {
  const swings = session.swings as Array<Record<string, unknown>>;
  const caveats: string[] = [];

  // THE rule this whole feature turns on. `gps_warning` means the watch was
  // reporting the paired iPhone's position, so each "shot distance" is the gap
  // between two cart positions. Those numbers are not merely imprecise, they
  // are measuring a different object — so they are removed rather than flagged,
  // because a flagged number in the input is still a number to reason about.
  const gpsWarning =
    typeof session.gps_warning === "string" && session.gps_warning.length > 0
      ? session.gps_warning
      : null;

  const measured = swings.filter(
    (s) => typeof s.distance_yd === "number" && Number.isFinite(s.distance_yd),
  );
  // Chips and putts are excluded from the bag stats. Left in, a cluster of
  // 20 yd chips reads as a club band, and the gap to the next real club shows
  // up as a missing wedge that is not missing.
  const fullSwings = measured.filter((s) => s.short_shot !== true);
  const shortShots = measured.length - fullSwings.length;

  let fullShots: Stat | null = null;
  let longestYd: number | null = null;
  let distancesWithheld = false;

  if (gpsWarning) {
    distancesWithheld = measured.length > 0;
    if (distancesWithheld) {
      caveats.push(
        `Distances withheld: the watch flagged its GPS as coming from the paired ` +
          `iPhone, not the wrist (${gpsWarning}). With the phone in the cart, every ` +
          `"shot" is the distance between two cart positions. ${measured.length} ` +
          `measurement(s) were dropped rather than analysed.`,
      );
    } else {
      caveats.push(`The watch flagged a GPS problem: ${gpsWarning}`);
    }
  } else {
    fullShots = summarise(numbersFrom(fullSwings, "distance_yd"), 1);
    longestYd = fullShots ? fullShots.max : null;
  }

  const tempo = summarise(numbersFrom(swings, "tempo_ratio"), 2);
  const peakG = summarise(numbersFrom(swings, "peak_g"), 2);

  // Short-shot yardages masked out, but the swings themselves kept in place.
  //
  // Passing the FILTERED list instead would hand `splitOf` a 12-element array
  // for a 24-swing round, and it would dutifully split that in half — comparing
  // swings 13-18 against 19-24 and reporting it as front nine versus back. The
  // halves have to be halves of the round, so the masking happens per reading
  // and the ordering stays intact.
  const distanceSource = swings.map((s) =>
    s.short_shot === true ? { ...s, distance_yd: undefined } : s,
  );

  const splits: Split[] = [];
  for (const [key, metric, places] of [
    ["distance_yd", "distance_yd", 1],
    ["tempo_ratio", "tempo_ratio", 2],
    ["peak_g", "peak_g", 2],
  ] as const) {
    // Distance splits inherit the withholding: an unreliable yardage is no more
    // usable as a fatigue trend than it is as a club distance.
    if (key === "distance_yd" && gpsWarning) continue;
    const source = key === "distance_yd" ? distanceSource : swings;
    const split = splitOf(source, key, metric, places);
    if (split) splits.push(split);
  }

  const longWaits = swings.filter((s) => s.long_wait === true).length;

  // Sample-rate honesty: a session logged at 62 Hz has coarser tempo phases
  // than one logged at 100, and the ratio should be read accordingly.
  const rate =
    typeof session.sample_rate_hz === "number" && Number.isFinite(session.sample_rate_hz)
      ? session.sample_rate_hz
      : null;
  if (rate !== null && rate < 80 && rate > 1) {
    caveats.push(
      `Motion was sampled at ${rate} Hz, below the 100 Hz the tempo maths assumes. ` +
        `Backswing and downswing timings are correspondingly coarse.`,
    );
  }

  if (tempo && tempo.n < swings.length) {
    caveats.push(
      `Tempo was only resolvable on ${tempo.n} of ${swings.length} swings — the rest ` +
        `had no still address to measure the backswing from, which is normal when ` +
        `you walk straight up to the ball and hit it.`,
    );
  }

  if (longWaits > 0) {
    caveats.push(
      `${longWaits} shot(s) followed a long stop. That is a tee wait or a lost ball, ` +
        `not necessarily a slow swing.`,
    );
  }

  if (!gpsWarning && fullShots === null && measured.length === 0) {
    caveats.push(
      `No shot distances in this session — distance needs a GPS fix on two ` +
        `consecutive swings.`,
    );
  }

  const first = swings.find((s) => typeof s.timestamp === "string");
  const date =
    typeof first?.timestamp === "string" ? first.timestamp.slice(0, 10) : null;

  return {
    date,
    mode: typeof session.mode === "string" ? session.mode : "unknown",
    swingCount: swings.length,
    durationMin: minutesBetween(swings),
    sampleRateHz: rate,
    tempo,
    fullShots,
    longestYd,
    shortShots,
    peakG,
    splits,
    longWaits,
    distancesWithheld,
    caveats,
    whoop: whoop ? whoopFactsFrom(whoop) : null,
  };
}
