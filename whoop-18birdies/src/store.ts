import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import { paths } from "./config.ts";
import { type Round, dedupeRounds } from "./rounds/types.ts";
import { type WhoopSnapshot, emptySnapshot } from "./whoop/types.ts";

/**
 * Reads a JSON store, returning `fallback` only when the file does not yet
 * exist. A corrupt or unreadable file throws instead: silently treating a
 * truncated store as empty would let the next save overwrite it with just the
 * incoming data, destroying every prior round. Failing loud keeps the damaged
 * file intact for recovery.
 */
async function readJson<T>(file: string, fallback: T): Promise<T> {
  let text: string;
  try {
    text = await readFile(file, "utf8");
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return fallback;
    throw err;
  }
  try {
    return JSON.parse(text) as T;
  } catch (err) {
    throw new Error(
      `Store at ${file} is not valid JSON — refusing to overwrite it. ` +
        `Move it aside to start fresh. (${(err as Error).message})`,
    );
  }
}

/**
 * Writes JSON atomically: a temp file in the same directory, then a rename.
 * An interrupted write can only damage the temp file, so the previous good
 * store always survives a crash mid-save.
 */
async function writeJson(file: string, value: unknown): Promise<void> {
  await mkdir(dirname(file), { recursive: true });
  const tmp = `${file}.tmp`;
  await writeFile(tmp, JSON.stringify(value, null, 2));
  await rename(tmp, file);
}

export function loadRounds(): Promise<Round[]> {
  return readJson<Round[]>(paths.rounds(), []);
}

/** Merges new rounds into the store, preferring the richer record per id. */
export async function saveRounds(rounds: Round[]): Promise<Round[]> {
  const merged = dedupeRounds([...(await loadRounds()), ...rounds]);
  await writeJson(paths.rounds(), merged);
  return merged;
}

export function loadSnapshot(): Promise<WhoopSnapshot> {
  return readJson<WhoopSnapshot>(paths.whoopCache(), emptySnapshot());
}

export function saveSnapshot(snapshot: WhoopSnapshot): Promise<void> {
  return writeJson(paths.whoopCache(), snapshot);
}

/** A swing session posted by the watch app, matching the logger's file wrapper. */
export interface WatchSession {
  mode: string;
  swings: Array<{ timestamp?: string; [key: string]: unknown }>;
  [key: string]: unknown;
}

/**
 * Persists a watch session under a filename derived from its first swing's
 * date, so repeat uploads on different days do not overwrite each other. A
 * second session on the same date is suffixed rather than clobbering the first.
 */
export async function saveWatchSession(
  session: WatchSession,
): Promise<{ path: string; name: string }> {
  const first = session.swings[0]?.timestamp;
  const date =
    typeof first === "string" && /^\d{4}-\d{2}-\d{2}/.test(first)
      ? first.slice(0, 10)
      : "undated";

  // Avoid overwriting an earlier session that shares the date.
  let name = `${session.mode}-${date}`;
  let candidate = paths.watchSession(name);
  for (let n = 2; await exists(candidate); n++) {
    name = `${session.mode}-${date}-${n}`;
    candidate = paths.watchSession(name);
  }

  await writeJson(candidate, session);
  return { path: candidate, name };
}

async function exists(file: string): Promise<boolean> {
  try {
    await readFile(file);
    return true;
  } catch {
    return false;
  }
}
