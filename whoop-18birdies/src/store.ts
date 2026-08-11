import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import { paths } from "./config.ts";
import { type Round, dedupeRounds } from "./rounds/types.ts";
import { type WhoopSnapshot, emptySnapshot } from "./whoop/types.ts";

async function readJson<T>(file: string, fallback: T): Promise<T> {
  try {
    return JSON.parse(await readFile(file, "utf8")) as T;
  } catch {
    return fallback;
  }
}

async function writeJson(file: string, value: unknown): Promise<void> {
  await mkdir(dirname(file), { recursive: true });
  await writeFile(file, JSON.stringify(value, null, 2));
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
