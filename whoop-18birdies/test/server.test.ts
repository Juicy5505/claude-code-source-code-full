import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { roundFromLoose, roundsFromPayload } from "../src/rounds/ingest.ts";

describe("loose round normalisation", () => {
  test("accepts Shortcuts-style keys and stringified numbers", () => {
    const round = roundFromLoose({
      Date: "2026-05-04",
      "Course Name": "Torrey Pines South",
      Holes: "18",
      Par: "72",
      Gross: "86",
      "Total Putts": "34",
    })!;
    expect(round.date).toBe("2026-05-04");
    expect(round.course).toBe("Torrey Pines South");
    expect(round.holes).toBe(18);
    expect(round.score).toBe(86);
    expect(round.putts).toBe(34);
  });

  test("derives the date from a tee time when no date field is sent", () => {
    const round = roundFromLoose({ start_time: "2026-05-04T08:10:00-07:00" })!;
    expect(round.date).toBe("2026-05-04");
    expect(round.startedAt).toBe("2026-05-04T15:10:00.000Z");
  });

  test("returns null with neither a date nor a start time", () => {
    expect(roundFromLoose({ course: "Torrey Pines", score: 86 })).toBeNull();
  });

  test("drops an unparseable timestamp instead of storing garbage", () => {
    const round = roundFromLoose({ date: "2026-05-04", endTime: "sometime after lunch" })!;
    expect(round.endedAt).toBeUndefined();
  });

  test("ignores unknown keys", () => {
    const round = roundFromLoose({ date: "2026-05-04", weather: "windy", mood: "grim" })!;
    expect(round.date).toBe("2026-05-04");
    expect(round.notes).toBeUndefined();
  });

  test("unwraps arrays and common wrapper objects", () => {
    expect(roundsFromPayload([{ date: "2026-05-04" }, { date: "2026-05-05" }])).toHaveLength(2);
    expect(roundsFromPayload({ rounds: [{ date: "2026-05-04" }] })).toHaveLength(1);
    expect(roundsFromPayload({ data: [{ date: "2026-05-04" }] })).toHaveLength(1);
    expect(roundsFromPayload({ date: "2026-05-04" })).toHaveLength(1);
  });

  test("yields nothing for payloads with no usable round", () => {
    expect(roundsFromPayload({ rounds: [] })).toHaveLength(0);
    expect(roundsFromPayload("not an object")).toHaveLength(0);
    expect(roundsFromPayload(null)).toHaveLength(0);
  });
});

describe("ingest server", () => {
  const TOKEN = "test-token-value";
  let dir: string;
  // The store reads WB_DATA_DIR at call time, and createHandler is imported
  // fresh per test file, so pointing it at a temp dir here is enough.
  let handle: (req: Request) => Promise<Response>;

  beforeEach(async () => {
    dir = mkdtempSync(join(tmpdir(), "wb-test-"));
    process.env.WB_DATA_DIR = dir;
    const { createHandler } = await import("../src/server.ts");
    handle = createHandler({ token: TOKEN });
  });

  afterEach(() => {
    rmSync(dir, { recursive: true, force: true });
    delete process.env.WB_DATA_DIR;
  });

  const post = (body: unknown, token = TOKEN) =>
    handle(
      new Request("http://localhost/rounds", {
        method: "POST",
        headers: { authorization: `Bearer ${token}` },
        body: JSON.stringify(body),
      }),
    );

  test("health check needs no auth", async () => {
    const res = await handle(new Request("http://localhost/health"));
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ ok: true });
  });

  test("rejects a missing or wrong token", async () => {
    expect((await handle(new Request("http://localhost/rounds", { method: "POST" }))).status).toBe(401);
    expect((await post({ date: "2026-05-04" }, "wrong")).status).toBe(401);
  });

  test("accepts a token via query param, for Shortcuts", async () => {
    const res = await handle(
      new Request(`http://localhost/rounds?token=${TOKEN}`, {
        method: "POST",
        body: JSON.stringify({ date: "2026-05-04", score: 86, par: 72 }),
      }),
    );
    expect(res.status).toBe(200);
  });

  test("stores a posted round and reports counts", async () => {
    const res = await post({ date: "2026-05-04", course: "Torrey", holes: 18, par: 72, score: 86 });
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ accepted: 1, stored: 1, dates: ["2026-05-04"] });
  });

  test("re-posting the same round does not duplicate it", async () => {
    await post({ date: "2026-05-04", course: "Torrey", holes: 18, par: 72, score: 86 });
    const second = await post({ date: "2026-05-04", course: "Torrey", holes: 18, par: 72, score: 86 });
    expect(await second.json()).toMatchObject({ stored: 1 });
  });

  test("rejects malformed JSON and unusable payloads distinctly", async () => {
    const bad = await handle(
      new Request("http://localhost/rounds", {
        method: "POST",
        headers: { authorization: `Bearer ${TOKEN}` },
        body: "{not json",
      }),
    );
    expect(bad.status).toBe(400);
    expect(await bad.json()).toMatchObject({ error: "body must be JSON" });

    const empty = await post({ course: "no date here" });
    expect(empty.status).toBe(400);
    expect(await empty.json()).toMatchObject({ error: "no rounds found in payload" });
  });

  test("readiness reports 404 when the date has no WHOOP data", async () => {
    const res = await handle(
      new Request(`http://localhost/readiness?date=2020-01-01&token=${TOKEN}`),
    );
    expect(res.status).toBe(404);
    expect(await res.json()).toMatchObject({ available: false });
  });

  test("readiness returns a phone-ready summary when data exists", async () => {
    const HOUR = 3_600_000;
    writeFileSync(
      join(dir, "whoop-cache.json"),
      JSON.stringify({
        fetchedAt: new Date().toISOString(),
        cycles: [
          {
            id: "c1",
            start: "2026-05-04T13:00:00.000Z",
            end: null,
            timezone_offset: "-07:00",
            score_state: "SCORED",
            score: { strain: 9, kilojoule: 8000, average_heart_rate: 70, max_heart_rate: 150 },
          },
        ],
        recoveries: [
          {
            cycle_id: "c1",
            sleep_id: "s1",
            score_state: "SCORED",
            score: { recovery_score: 88, resting_heart_rate: 52, hrv_rmssd_milli: 74 },
          },
        ],
        sleeps: [
          {
            id: "s1",
            start: "2026-05-04T08:00:00.000Z",
            end: "2026-05-04T13:00:00.000Z",
            timezone_offset: "-07:00",
            nap: false,
            score_state: "SCORED",
            score: {
              sleep_performance_percentage: 92,
              stage_summary: {
                total_in_bed_time_milli: 8.5 * HOUR,
                total_awake_time_milli: 0.5 * HOUR,
                total_light_sleep_time_milli: 0,
                total_slow_wave_sleep_time_milli: 0,
                total_rem_sleep_time_milli: 0,
                sleep_cycle_count: 5,
                disturbance_count: 1,
              },
            },
          },
        ],
        workouts: [],
      }),
    );

    const res = await handle(
      new Request(`http://localhost/readiness?date=2026-05-04&token=${TOKEN}`),
    );
    expect(res.status).toBe(200);
    const body = (await res.json()) as { score: number; verdict: string; summary: string };
    expect(body.score).toBeGreaterThan(75);
    expect(body.verdict).toBe("prime");
    expect(body.summary).toMatch(/Golf readiness \d+\/100/);
  });

  test("unknown routes 404", async () => {
    const res = await handle(new Request(`http://localhost/nope?token=${TOKEN}`));
    expect(res.status).toBe(404);
  });

  test("a cached-but-unscored day is unavailable, never 'NaN/100'", async () => {
    // A cycle exists for the date but its recovery is PENDING_SCORE, so
    // computeReadiness returns NaN. The response must be a clean 404, and the
    // summary must never carry the literal 'NaN'.
    writeFileSync(
      join(dir, "whoop-cache.json"),
      JSON.stringify({
        fetchedAt: new Date().toISOString(),
        cycles: [
          {
            id: "c1",
            start: "2026-05-04T13:00:00.000Z",
            end: null,
            timezone_offset: "-07:00",
            score_state: "PENDING_SCORE",
          },
        ],
        recoveries: [
          { cycle_id: "c1", sleep_id: "s1", score_state: "PENDING_SCORE" },
        ],
        sleeps: [],
        workouts: [],
      }),
    );
    const res = await handle(
      new Request(`http://localhost/readiness?date=2026-05-04&token=${TOKEN}`),
    );
    expect(res.status).toBe(404);
    const body = (await res.json()) as { available: boolean; message?: string };
    expect(body.available).toBe(false);
    expect(JSON.stringify(body)).not.toContain("NaN");
  });

  test("a truncated store fails loud instead of clobbering it", async () => {
    // A corrupt rounds.json must not be silently treated as empty and
    // overwritten — that would destroy every prior round.
    const { saveRounds } = await import("../src/store.ts");
    writeFileSync(join(dir, "rounds.json"), "{ this is not valid json");
    await expect(
      saveRounds([{ id: "x", date: "2026-05-04", holes: 18, source: "manual" }]),
    ).rejects.toThrow(/not valid JSON/);
  });
});

describe("token comparison", () => {
  test("matches only the exact token", async () => {
    const { tokenMatches } = await import("../src/server.ts");
    expect(tokenMatches("abc123", "abc123")).toBe(true);
    expect(tokenMatches("abc123", "abc124")).toBe(false);
    // Different lengths must not throw, which timingSafeEqual does on its own.
    expect(tokenMatches("abc123", "abc")).toBe(false);
    expect(tokenMatches("abc123", "")).toBe(false);
  });
});
