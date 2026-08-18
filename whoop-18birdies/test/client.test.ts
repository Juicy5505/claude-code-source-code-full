import { afterEach, describe, expect, test } from "bun:test";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { WhoopClient } from "../src/whoop/client.ts";

function jsonResponse(body: unknown, init: ResponseInit = {}): Response {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { "content-type": "application/json" },
    ...init,
  });
}

function clientWith(responses: Response[], calls: string[] = []) {
  let i = 0;
  const fetchImpl = (async (url: string | URL | Request) => {
    calls.push(String(url));
    const res = responses[i++];
    if (!res) throw new Error("unexpected extra fetch call");
    return res;
  }) as unknown as typeof fetch;
  return new WhoopClient({ fetchImpl, getToken: async () => "test-token" });
}

describe("WhoopClient", () => {
  test("follows next_token across pages and concatenates records", async () => {
    const calls: string[] = [];
    const client = clientWith(
      [
        jsonResponse({ records: [{ id: "1" }], next_token: "tok2" }),
        jsonResponse({ records: [{ id: "2" }], next_token: null }),
      ],
      calls,
    );

    const cycles = await client.cycles();
    expect(cycles.map((c) => c.id)).toEqual(["1", "2"]);
    expect(calls[0]).toContain("limit=25");
    expect(calls[0]).not.toContain("nextToken");
    expect(calls[1]).toContain("nextToken=tok2");
  });

  test("sends the bearer token and the requested date range", async () => {
    // Held in an object because TS cannot see that the callback ran and would
    // otherwise narrow a plain `let` to `null` at the assertion below.
    const seen: { auth?: string | null } = {};
    const fetchImpl = (async (url: string | URL, init?: RequestInit) => {
      seen.auth = new Headers(init?.headers).get("authorization");
      expect(String(url)).toContain("start=2026-05-01T00%3A00%3A00.000Z");
      return jsonResponse({ records: [], next_token: null });
    }) as unknown as typeof fetch;

    const client = new WhoopClient({ fetchImpl, getToken: async () => "abc123" });
    await client.recoveries({
      start: new Date("2026-05-01T00:00:00.000Z"),
      end: new Date("2026-05-08T00:00:00.000Z"),
    });
    expect(seen.auth).toBe("Bearer abc123");
  });

  test("retries a 429 and then succeeds", async () => {
    const client = clientWith([
      new Response("rate limited", { status: 429, headers: { "retry-after": "0" } }),
      jsonResponse({ records: [{ id: "1" }], next_token: null }),
    ]);
    expect(await client.workouts()).toHaveLength(1);
  });

  test("does not retry a 401 and surfaces the body", async () => {
    const client = clientWith([new Response("bad token", { status: 401 })]);
    await expect(client.sleeps()).rejects.toThrow(/401.*bad token/s);
  });

  test("aborts rather than looping forever on a stuck next_token", async () => {
    const fetchImpl = (async () =>
      jsonResponse({ records: [{ id: "x" }], next_token: "always" })) as unknown as typeof fetch;
    const client = new WhoopClient({ fetchImpl, getToken: async () => "t", maxPages: 3 });
    await expect(client.cycles()).rejects.toThrow(/exceeded 3 pages/);
  });

  test("snapshot tolerates a profile call that fails", async () => {
    const fetchImpl = (async (url: string | URL) =>
      String(url).includes("/v2/user/profile/basic")
        ? new Response("forbidden", { status: 403 })
        : jsonResponse({ records: [], next_token: null })) as unknown as typeof fetch;

    const client = new WhoopClient({ fetchImpl, getToken: async () => "t" });
    const snap = await client.snapshot({
      start: new Date("2026-05-01T00:00:00.000Z"),
      end: new Date("2026-05-08T00:00:00.000Z"),
    });
    expect(snap.profile).toBeUndefined();
    expect(snap.cycles).toEqual([]);
  });
});

describe("id coercion (audit fix)", () => {
  test("numeric cycle ids from WHOOP become strings", async () => {
    const client = clientWith([
      jsonResponse({ records: [{ id: 12345, timezone_offset: "-07:00", score_state: "SCORED" }], next_token: null }),
    ]);
    const cycles = await client.cycles();
    expect(typeof cycles[0]!.id).toBe("string");
    expect(cycles[0]!.id).toBe("12345");
  });

  test("recovery join keys are coerced so they match string cycle ids", async () => {
    const client = clientWith([
      jsonResponse({ records: [{ cycle_id: 12345, sleep_id: 999, score_state: "SCORED" }], next_token: null }),
    ]);
    const recoveries = await client.recoveries();
    expect(recoveries[0]!.cycle_id).toBe("12345");
    expect(recoveries[0]!.sleep_id).toBe("999");
  });
});


describe("token handling under concurrency", () => {
  const dir = mkdtempSync(join(tmpdir(), "wb-oauth-"));

  afterEach(() => {
    delete process.env.WB_DATA_DIR;
    delete process.env.WHOOP_CLIENT_ID;
    delete process.env.WHOOP_CLIENT_SECRET;
  });

  test("a corrupt token file is reported, not read as 'never logged in'", async () => {
    const scratch = mkdtempSync(join(tmpdir(), "wb-oauth-bad-"));
    process.env.WB_DATA_DIR = scratch;
    writeFileSync(join(scratch, "tokens.json"), "{ truncated");
    const { loadTokens } = await import("../src/whoop/oauth.ts");
    // Reporting corruption as "not linked" sent people through `wb login`
    // again, which overwrote the file and destroyed a refresh token that might
    // still have been recoverable from it.
    await expect(loadTokens()).rejects.toThrow(/not valid JSON/);
    rmSync(scratch, { recursive: true, force: true });
  });

  test("an absent token file really is 'not linked'", async () => {
    const scratch = mkdtempSync(join(tmpdir(), "wb-oauth-none-"));
    process.env.WB_DATA_DIR = scratch;
    const { loadTokens } = await import("../src/whoop/oauth.ts");
    expect(await loadTokens()).toBeNull();
    rmSync(scratch, { recursive: true, force: true });
  });

  test("concurrent callers share ONE refresh", async () => {
    // snapshot() fetches cycles, recovery, sleep and workouts concurrently.
    // With an expired token all four used to fire their own refresh — four
    // rotations of the same single-use refresh token, of which only the last
    // survives, so the three losers wrote dead credentials over the live ones.
    process.env.WB_DATA_DIR = dir;
    process.env.WHOOP_CLIENT_ID = "test-client-id";
    process.env.WHOOP_CLIENT_SECRET = "test-client-secret";
    writeFileSync(
      join(dir, "tokens.json"),
      JSON.stringify({
        access_token: "stale",
        refresh_token: "rt-1",
        expires_at: Date.now() - 60_000, // already expired
        scope: "offline read:recovery",
      }),
    );

    let refreshCalls = 0;
    const realFetch = globalThis.fetch;
    globalThis.fetch = (async (_url: string, _init?: RequestInit) => {
      refreshCalls += 1;
      // A slow response widens the window in which a second caller could
      // start its own refresh, which is exactly what must not happen.
      await new Promise((r) => setTimeout(r, 25));
      return new Response(
        JSON.stringify({
          access_token: `fresh-${refreshCalls}`,
          refresh_token: `rt-${refreshCalls + 1}`,
          expires_in: 3600,
          scope: "offline read:recovery",
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      );
    }) as typeof fetch;

    try {
      const { getAccessToken } = await import("../src/whoop/oauth.ts");
      const tokens = await Promise.all([
        getAccessToken(),
        getAccessToken(),
        getAccessToken(),
        getAccessToken(),
      ]);
      expect(refreshCalls).toBe(1);
      expect(new Set(tokens).size).toBe(1);
    } finally {
      globalThis.fetch = realFetch;
      rmSync(dir, { recursive: true, force: true });
    }
  });

  test("a failed refresh does not wedge every later attempt", async () => {
    // The in-flight promise must be cleared on rejection too, or one transient
    // network failure poisons the process for as long as it runs.
    const scratch = mkdtempSync(join(tmpdir(), "wb-oauth-fail-"));
    process.env.WB_DATA_DIR = scratch;
    process.env.WHOOP_CLIENT_ID = "test-client-id";
    process.env.WHOOP_CLIENT_SECRET = "test-client-secret";
    writeFileSync(
      join(scratch, "tokens.json"),
      JSON.stringify({
        access_token: "stale",
        refresh_token: "rt-1",
        expires_at: Date.now() - 60_000,
        scope: "offline",
      }),
    );

    let attempts = 0;
    const realFetch = globalThis.fetch;
    globalThis.fetch = (async (_url: string, _init?: RequestInit) => {
      attempts += 1;
      if (attempts === 1) throw new Error("network down");
      return new Response(
        JSON.stringify({
          access_token: "recovered",
          refresh_token: "rt-2",
          expires_in: 3600,
          scope: "offline",
        }),
        { status: 200, headers: { "content-type": "application/json" } },
      );
    }) as typeof fetch;

    try {
      const { getAccessToken } = await import("../src/whoop/oauth.ts");
      await expect(getAccessToken()).rejects.toThrow();
      expect(await getAccessToken()).toBe("recovered");
    } finally {
      globalThis.fetch = realFetch;
      rmSync(scratch, { recursive: true, force: true });
    }
  });
});
