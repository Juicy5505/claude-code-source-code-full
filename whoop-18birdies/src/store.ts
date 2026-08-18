import { mkdir, readdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import { randomBytes } from "node:crypto";
import { dirname, join, resolve, sep } from "node:path";
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
  // A UNIQUE temp name per write. A fixed `${file}.tmp` means two concurrent
  // saves — `wb sync` while the ingest server stores a round, say — write over
  // each other's temp file and then both rename it, so one payload is lost and
  // the other may be a spliced mixture of the two.
  const tmp = `${file}.${process.pid}.${randomBytes(6).toString("hex")}.tmp`;
  try {
    // 0600: this holds WHOOP health data and round history. The default 0644
    // makes it readable by every account on the machine.
    await writeFile(tmp, JSON.stringify(value, null, 2), { mode: 0o600 });
    await rename(tmp, file);
  } catch (err) {
    await rm(tmp, { force: true }).catch(() => {});
    throw err;
  }
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
/**
 * Reduce a caller-supplied label to something safe to put in a filename.
 *
 * `mode` arrives in the request body, and it used to be concatenated straight
 * into a path. That is an arbitrary file write: `mode: "../../../../tmp/pwned"`
 * resolved to `/tmp/pwned-2026-08-17.json`, entirely outside the data
 * directory. Allow-listing the characters is the fix — a deny-list of "../"
 * misses `..%2f`, backslashes, absolute paths and NUL bytes.
 */
function safeLabel(value: unknown, fallback: string): string {
  const text = typeof value === "string" ? value : "";
  const cleaned = text.toLowerCase().replace(/[^a-z0-9_-]/g, "").slice(0, 32);
  return cleaned || fallback;
}

export async function saveWatchSession(
  session: WatchSession,
): Promise<{ path: string; name: string }> {
  const first = session.swings[0]?.timestamp;
  const date =
    typeof first === "string" && /^\d{4}-\d{2}-\d{2}/.test(first)
      ? first.slice(0, 10)
      : "undated";

  const mode = safeLabel(session.mode, "session");

  // Avoid overwriting an earlier session that shares the date.
  let name = `${mode}-${date}`;
  let candidate = paths.watchSession(name);
  for (let n = 2; await exists(candidate); n++) {
    name = `${mode}-${date}-${n}`;
    candidate = paths.watchSession(name);
  }

  // Belt and braces: even with the label sanitised, refuse to write anywhere
  // but inside the sessions directory. A future edit to the naming scheme
  // cannot silently reintroduce an escape.
  const root = resolve(paths.watchSessions());
  const target = resolve(candidate);
  if (target !== join(root, `${name}.json`) || !target.startsWith(root + sep)) {
    throw new Error("refusing to write a session outside the data directory");
  }

  await writeJson(candidate, session);
  return { path: candidate, name };
}

/**
 * Watch session names, most recent round first.
 *
 * Ordered by the date in the filename rather than by mtime. mtime is the moment
 * the file last landed on this disk, which for a session restored from a backup
 * or copied off another machine is today — so a round from March would sort as
 * the newest thing you played.
 */
export async function listWatchSessions(): Promise<string[]> {
  let entries: string[];
  try {
    entries = await readdir(paths.watchSessions());
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return [];
    throw err;
  }

  const dateOf = (name: string): string =>
    name.match(/\d{4}-\d{2}-\d{2}/)?.[0] ?? "";

  return entries
    .filter((name) => name.endsWith(".json"))
    .map((name) => name.slice(0, -".json".length))
    .sort((a, b) => {
      const byDate = dateOf(b).localeCompare(dateOf(a));
      // Undated sessions all compare equal on date; the name tiebreak keeps the
      // order stable rather than dependent on directory iteration order.
      return byDate !== 0 ? byDate : b.localeCompare(a);
    });
}

/** Reads one stored session by name. Throws if it is missing or corrupt. */
export async function loadWatchSession(name: string): Promise<WatchSession> {
  // Through the same sanitiser that named the file. A session name reaches
  // here from the command line, so `wb coach ../../tokens` must not resolve to
  // anything outside the sessions directory.
  const label = safeLabel(name, "");
  if (!label) throw new Error(`"${name}" is not a valid session name.`);
  const session = await readJson<WatchSession | null>(paths.watchSession(label), null);
  if (!session) throw new Error(`No stored session named "${name}".`);
  return session;
}

async function exists(file: string): Promise<boolean> {
  try {
    await readFile(file);
    return true;
  } catch {
    return false;
  }
}
