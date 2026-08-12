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
