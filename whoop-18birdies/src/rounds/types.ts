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

/** Stable id so re-importing the same source does not duplicate rounds. */
export function roundId(date: string, course: string | undefined, holes: number): string {
  const slug = (course ?? "unknown").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
  return `${date}_${slug}_${holes}`;
}

export function dedupeRounds(rounds: Round[]): Round[] {
  const byId = new Map<string, Round>();
  for (const r of rounds) {
    const existing = byId.get(r.id);
    // A hand-entered scorecard carries strokes and putts that an Apple Health
    // workout never will, so richer sources win ties.
    if (!existing || fieldCount(r) > fieldCount(existing)) byId.set(r.id, r);
  }
  return [...byId.values()].sort((a, b) => a.date.localeCompare(b.date));
}

function fieldCount(r: Round): number {
  return Object.values(r).filter((v) => v !== undefined && v !== null).length;
}
