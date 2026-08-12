export type RoundSource = "csv" | "apple-health" | "manual";

/**
 * One round of golf. Everything past `date` is optional because the amount of
 * detail 18Birdies lets you get back out varies by how the round was recorded
 * and how it was transcribed.
 */
export interface Round {
  id: string;
  /** Local calendar date, YYYY-MM-DD. This is the join key against WHOOP. */
  date: string;
  course?: string;
  holes: number;
  /** Gross strokes for the round. */
  score?: number;
  par?: number;
  putts?: number;
  fairwaysHit?: number;
  fairwaysPossible?: number;
  greensInRegulation?: number;
  startedAt?: string;
  endedAt?: string;
  source: RoundSource;
  notes?: string;
}

/**
 * Strokes over par, normalised to 18 holes so 9- and 18-hole rounds can sit in
 * the same regression. Returns null when either side is unknown.
 */
export function scoreToPar(round: Round): number | null {
  if (round.score == null || round.par == null) return null;
  const diff = round.score - round.par;
  return round.holes === 9 ? diff * 2 : diff;
}

export function roundDurationMinutes(round: Round): number | null {
  if (!round.startedAt || !round.endedAt) return null;
  const ms = Date.parse(round.endedAt) - Date.parse(round.startedAt);
  return Number.isFinite(ms) && ms > 0 ? ms / 60_000 : null;
}

/**
 * Stable id so re-importing the same source does not duplicate rounds, and so a
 * sparse Apple Health workout and a rich CSV scorecard for the same round merge.
 *
 * Known limit: two genuinely distinct rounds at the same course, same day, same
 * hole count (a morning and afternoon 18, say) share an id and are merged rather
 * than kept apart. Adding a tee-time component would separate them but would
 * also stop the cross-source merge — Apple Health carries a start time and a
 * hand-typed CSV usually does not — so the common case is preserved over the
 * rare one. Disambiguate a genuine double round by giving them distinct course
 * names in the CSV.
 */
export function roundId(date: string, course: string | undefined, holes: number): string {
  const slug = (course ?? "unknown").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
  return `${date}_${slug}_${holes}`;
}

export function dedupeRounds(rounds: Round[]): Round[] {
  const byId = new Map<string, Round>();
  for (const r of rounds) {
    const existing = byId.get(r.id);
    byId.set(r.id, existing ? mergeRounds(existing, r) : r);
  }
  return [...byId.values()].sort((a, b) => a.date.localeCompare(b.date));
}

/**
 * Combines two records with the same id. Each present (non-null) field of the
 * later record wins — a re-submission is treated as a correction — while fields
 * only the earlier record carries are kept. So a rich source and a sparse one
 * merge instead of one clobbering the other, and a corrected score with the
 * same populated-field count is no longer silently dropped.
 */
export function mergeRounds(existing: Round, incoming: Round): Round {
  const out = { ...existing } as unknown as Record<string, unknown>;
  for (const [key, value] of Object.entries(incoming)) {
    if (value !== undefined && value !== null) {
      out[key] = value;
    }
  }
  return out as unknown as Round;
}
