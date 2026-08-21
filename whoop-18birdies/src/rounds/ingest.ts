import { normaliseDate } from "./csv.ts";
import { type Round, roundId } from "./types.ts";

/**
 * Normalises a loose key/value record into a Round.
 *
 * Used by the ingest server, where payloads come from Apple Shortcuts. Shortcuts
 * dictionaries are hand-built by the user, so key naming and value types vary —
 * numbers routinely arrive as strings, and capitalisation is whatever they
 * typed. This accepts that rather than demanding an exact schema.
 */

const KEYS: Record<string, string[]> = {
  date: ["date", "rounddate", "playedon", "day"],
  course: ["course", "coursename", "club", "location"],
  holes: ["holes", "holecount"],
  score: ["score", "gross", "strokes", "total", "grossscore"],
  par: ["par", "coursepar"],
  putts: ["putts", "totalputts"],
  fairwaysHit: ["fairways", "fairwayshit", "fir"],
  fairwaysPossible: ["fairwayspossible", "fairwayattempts"],
  greensInRegulation: ["gir", "greens", "greensinregulation"],
  startedAt: ["start", "startedat", "starttime", "teetime", "startdate"],
  endedAt: ["end", "endedat", "endtime", "enddate"],
  notes: ["notes", "note", "comment", "comments"],
};

function canonicalKey(raw: string): string | null {
  const norm = raw.trim().toLowerCase().replace(/[\s_-]/g, "");
  for (const [key, aliases] of Object.entries(KEYS)) {
    if (aliases.includes(norm)) return key;
  }
  return null;
}

/** Shortcuts sends numbers as strings often enough that this must accept both. */
function toNumber(value: unknown): number | undefined {
  if (typeof value === "number") return Number.isFinite(value) ? value : undefined;
  if (typeof value === "string") {
    const t = value.trim();
    if (t === "") return undefined;
    const n = Number(t);
    return Number.isFinite(n) ? n : undefined;
  }
  return undefined;
}

function toText(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const t = value.trim();
  return t === "" ? undefined : t;
}

/** ISO 8601 if parseable, otherwise dropped — a bad timestamp is worse than none. */
function toIso(value: unknown): string | undefined {
  const text = toText(value);
  if (!text) return undefined;
  const ms = Date.parse(text);
  return Number.isFinite(ms) ? new Date(ms).toISOString() : undefined;
}

export function roundFromLoose(input: Record<string, unknown>): Round | null {
  const rec: Record<string, unknown> = {};
  for (const [rawKey, value] of Object.entries(input)) {
    const key = canonicalKey(rawKey);
    if (key) rec[key] = value;
  }

  const startedAt = toIso(rec.startedAt);
  // Fall back to the tee time's calendar date so a Shortcut that only sends a
  // workout's start/end still produces a joinable round. Derive it from the RAW
  // local timestamp, never from `startedAt` — that has been converted to UTC,
  // which shifts an evening tee time in a western zone onto the next day and
  // breaks the WHOOP join. `date` is documented as the LOCAL calendar date.
  const rawDate = toText(rec.date) ?? toText(rec.startedAt);
  if (!rawDate) return null;
  const date = normaliseDate(rawDate);
  if (!date) return null;

  const holes = toNumber(rec.holes) ?? 18;
  const course = toText(rec.course);

  return {
    id: roundId(date, course, holes),
    date,
    course,
    holes,
    score: toNumber(rec.score),
    par: toNumber(rec.par),
    putts: toNumber(rec.putts),
    fairwaysHit: toNumber(rec.fairwaysHit),
    fairwaysPossible: toNumber(rec.fairwaysPossible),
    greensInRegulation: toNumber(rec.greensInRegulation),
    startedAt,
    endedAt: toIso(rec.endedAt),
    source: "manual",
    notes: toText(rec.notes),
  };
}

/**
 * Pulls rounds out of whatever shape the payload arrived in. Shortcuts can send
 * a bare dictionary, a list of dictionaries, or a wrapper object depending on
 * how the "Get Contents of URL" action was configured.
 */
export function roundsFromPayload(payload: unknown): Round[] {
  if (Array.isArray(payload)) {
    return payload.flatMap((item) => roundsFromPayload(item));
  }
  if (payload === null || typeof payload !== "object") return [];

  const obj = payload as Record<string, unknown>;
  for (const wrapper of ["rounds", "items", "records", "data"]) {
    if (Array.isArray(obj[wrapper])) return roundsFromPayload(obj[wrapper]);
  }

  const round = roundFromLoose(obj);
  return round ? [round] : [];
}
