import { type Round, roundId } from "./types.ts";

/**
 * Minimal RFC4180 parser. Handles quoted fields, embedded commas/newlines, and
 * doubled quotes — all of which show up in course names like
 * `Pebble Beach, "Old" Course`.
 */
export function parseCsv(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = "";
  let inQuotes = false;

  // Strip a UTF-8 BOM; spreadsheet exports frequently carry one and it would
  // otherwise corrupt the first header name.
  const src = text.replace(/^﻿/, "");

  for (let i = 0; i < src.length; i++) {
    const c = src[i];
    if (inQuotes) {
      if (c === '"') {
        if (src[i + 1] === '"') {
          field += '"';
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field += c;
      }
      continue;
    }
    if (c === '"') {
      inQuotes = true;
    } else if (c === ",") {
      row.push(field);
      field = "";
    } else if (c === "\n" || c === "\r") {
      if (c === "\r" && src[i + 1] === "\n") i++;
      row.push(field);
      rows.push(row);
      row = [];
      field = "";
    } else {
      field += c;
    }
  }
  if (field.length > 0 || row.length > 0) {
    row.push(field);
    rows.push(row);
  }
  return rows.filter((r) => r.some((cell) => cell.trim() !== ""));
}

/** Header aliases, so a scorecard transcribed by hand does not need exact names. */
const ALIASES: Record<string, string[]> = {
  date: ["date", "round date", "played", "day"],
  course: ["course", "course name", "club"],
  holes: ["holes", "hole count", "# holes"],
  score: ["score", "gross", "strokes", "total", "gross score"],
  par: ["par", "course par"],
  putts: ["putts", "total putts"],
  fairwaysHit: ["fairways", "fairways hit", "fir"],
  fairwaysPossible: ["fairways possible", "fairway attempts", "possible fairways"],
  greensInRegulation: ["gir", "greens", "greens in regulation"],
  startedAt: ["start", "started at", "tee time", "start time"],
  endedAt: ["end", "ended at", "finish time", "end time"],
  notes: ["notes", "comment", "comments"],
};

function buildHeaderMap(header: string[]): Map<number, string> {
  const map = new Map<number, string>();
  header.forEach((raw, idx) => {
    const norm = raw.trim().toLowerCase();
    for (const [key, aliases] of Object.entries(ALIASES)) {
      if (aliases.includes(norm)) {
        map.set(idx, key);
        return;
      }
    }
  });
  return map;
}

function num(value: string | undefined): number | undefined {
  if (value == null) return undefined;
  const t = value.trim();
  if (t === "") return undefined;
  const n = Number(t);
  return Number.isFinite(n) ? n : undefined;
}

/**
 * Normalises the date column to YYYY-MM-DD. Accepts ISO and US M/D/YYYY, which
 * covers what people actually type off an 18Birdies scorecard.
 */
export function normaliseDate(value: string): string | null {
  const t = value.trim();
  const iso = /^(\d{4})-(\d{2})-(\d{2})/.exec(t);
  if (iso) return `${iso[1]}-${iso[2]}-${iso[3]}`;

  const us = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(t);
  if (us) {
    const [, m, d, y] = us;
    return `${y}-${m!.padStart(2, "0")}-${d!.padStart(2, "0")}`;
  }

  const parsed = Date.parse(t);
  if (!Number.isFinite(parsed)) return null;
  return new Date(parsed).toISOString().slice(0, 10);
}

export function roundsFromCsv(text: string): Round[] {
  const rows = parseCsv(text);
  if (rows.length < 2) return [];

  const headerMap = buildHeaderMap(rows[0]!);
  if (![...headerMap.values()].includes("date")) {
    throw new Error(
      `CSV needs a 'date' column. Got: ${rows[0]!.join(", ")}`,
    );
  }

  const out: Round[] = [];
  for (const row of rows.slice(1)) {
    const rec: Record<string, string> = {};
    headerMap.forEach((key, idx) => {
      rec[key] = row[idx] ?? "";
    });

    const date = normaliseDate(rec.date ?? "");
    if (!date) continue;

    const holes = num(rec.holes) ?? 18;
    const course = rec.course?.trim() || undefined;

    out.push({
      id: roundId(date, course, holes),
      date,
      course,
      holes,
      score: num(rec.score),
      par: num(rec.par),
      putts: num(rec.putts),
      fairwaysHit: num(rec.fairwaysHit),
      fairwaysPossible: num(rec.fairwaysPossible),
      greensInRegulation: num(rec.greensInRegulation),
      startedAt: rec.startedAt?.trim() || undefined,
      endedAt: rec.endedAt?.trim() || undefined,
      source: "csv",
      notes: rec.notes?.trim() || undefined,
    });
  }
  return out;
}

export const CSV_TEMPLATE = `date,course,holes,par,score,putts,fairways hit,fairways possible,gir,start time,notes
2026-05-04,Torrey Pines South,18,72,86,34,6,14,5,2026-05-04T08:10:00-07:00,windy back nine
`;
