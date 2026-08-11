import type { DayPhysiology, MetricCorrelation } from "./correlate.ts";

/**
 * A "golf readiness" read for a given day.
 *
 * This is a heuristic, not a WHOOP metric — WHOOP has no golf readiness score.
 * It weights recovery, sleep and prior-day strain, which are the inputs most
 * plausibly connected to four hours of walking and repeated rotational effort.
 * Once enough scored rounds exist, `personalise` re-weights it against what
 * actually correlates with the user's own scoring.
 */

export interface ReadinessComponent {
  label: string;
  /** Normalised 0-100 contribution before weighting. */
  value: number;
  weight: number;
  detail: string;
}

export interface Readiness {
  score: number;
  verdict: "prime" | "solid" | "manage" | "compromised";
  components: ReadinessComponent[];
  advice: string[];
  /** True when weights came from the user's own round history. */
  personalised: boolean;
}

const BASE_WEIGHTS = {
  recoveryScore: 0.5,
  sleepHours: 0.3,
  priorDayStrain: 0.2,
} as const;

type WeightKey = keyof typeof BASE_WEIGHTS;

/** Sleep utility: rises to 8 h and flattens, rather than rewarding 11 h in bed. */
export function sleepUtility(hours: number): number {
  if (hours <= 4) return 0;
  if (hours >= 8) return 100;
  return ((hours - 4) / 4) * 100;
}

/** Prior-day strain: WHOOP strain is 0-21; more strain yesterday scores lower today. */
export function strainUtility(strain: number): number {
  const clamped = Math.max(0, Math.min(21, strain));
  return 100 - (clamped / 21) * 100;
}

/**
 * Re-weights the components using the user's own correlations. Metrics that
 * track their scoring more strongly get more say. Only correlations from at
 * least 8 rounds are trusted; below that the sample is noise.
 */
export function personalise(
  correlations: MetricCorrelation[],
): { weights: Record<WeightKey, number>; personalised: boolean } {
  const usable = correlations.filter(
    (c) => c.n >= 8 && Number.isFinite(c.pearson) && c.key in BASE_WEIGHTS,
  );
  if (usable.length === 0) {
    return { weights: { ...BASE_WEIGHTS }, personalised: false };
  }

  const raw: Record<string, number> = {};
  let total = 0;
  for (const key of Object.keys(BASE_WEIGHTS) as WeightKey[]) {
    const found = usable.find((c) => c.key === key);
    // Blend toward the observed strength rather than replacing the prior
    // outright, so one lucky round cannot dominate the weighting.
    const strength = found ? Math.abs(found.pearson) : 0;
    const w = BASE_WEIGHTS[key] * (1 + strength);
    raw[key] = w;
    total += w;
  }

  const weights = {} as Record<WeightKey, number>;
  for (const key of Object.keys(BASE_WEIGHTS) as WeightKey[]) {
    weights[key] = raw[key]! / total;
  }
  return { weights, personalised: true };
}

export function computeReadiness(
  day: DayPhysiology,
  correlations: MetricCorrelation[] = [],
): Readiness {
  const { weights, personalised } = personalise(correlations);
  const components: ReadinessComponent[] = [];

  if (day.recoveryScore != null) {
    components.push({
      label: "Recovery",
      value: Math.max(0, Math.min(100, day.recoveryScore)),
      weight: weights.recoveryScore,
      detail: `${day.recoveryScore.toFixed(0)}%${
        day.hrvMs != null ? ` · HRV ${day.hrvMs.toFixed(0)} ms` : ""
      }`,
    });
  }
  if (day.sleepHours != null) {
    components.push({
      label: "Sleep",
      value: sleepUtility(day.sleepHours),
      weight: weights.sleepHours,
      detail: `${day.sleepHours.toFixed(1)} h asleep`,
    });
  }
  if (day.priorDayStrain != null) {
    components.push({
      label: "Freshness",
      value: strainUtility(day.priorDayStrain),
      weight: weights.priorDayStrain,
      detail: `prior-day strain ${day.priorDayStrain.toFixed(1)}`,
    });
  }

  if (components.length === 0) {
    return {
      score: Number.NaN,
      verdict: "manage",
      components: [],
      advice: ["No WHOOP data for this date — run `wb sync` and try again."],
      personalised,
    };
  }

  // Re-normalise across present components so a missing input does not silently
  // drag the score toward zero.
  const weightSum = components.reduce((a, c) => a + c.weight, 0);
  const score = components.reduce((a, c) => a + c.value * (c.weight / weightSum), 0);

  return {
    score,
    verdict: verdictFor(score),
    components,
    advice: adviceFor(score, day),
    personalised,
  };
}

function verdictFor(score: number): Readiness["verdict"] {
  if (score >= 75) return "prime";
  if (score >= 55) return "solid";
  if (score >= 35) return "manage";
  return "compromised";
}

function adviceFor(score: number, day: DayPhysiology): string[] {
  const advice: string[] = [];
  if (score >= 75) {
    advice.push("Green light — this is a day to be aggressive off the tee.");
  } else if (score >= 55) {
    advice.push("Normal game plan. Nothing physiological to work around.");
  } else if (score >= 35) {
    advice.push("Play conservative targets; expect the back nine to cost you.");
  } else {
    advice.push("Low readiness — consider a cart, 9 holes, or the range instead.");
  }

  if (day.sleepHours != null && day.sleepHours < 6) {
    advice.push(
      `Only ${day.sleepHours.toFixed(1)} h of sleep — short sleep tends to hit putting and late-round focus first.`,
    );
  }
  if (day.priorDayStrain != null && day.priorDayStrain >= 14) {
    advice.push(
      `Prior-day strain was ${day.priorDayStrain.toFixed(1)} — warm up longer than usual.`,
    );
  }
  if (day.recoveryScore != null && day.recoveryScore < 34) {
    advice.push("WHOOP has you in the red; hydration and pace matter more than distance today.");
  }
  return advice;
}
