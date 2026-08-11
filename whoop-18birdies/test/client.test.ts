import { describe, expect, test } from "bun:test";
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
