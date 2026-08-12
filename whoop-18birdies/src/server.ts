import { timingSafeEqual } from "node:crypto";
import { indexPhysiology, linkRounds, summarise } from "./link/correlate.ts";
import { computeReadiness } from "./link/readiness.ts";
import { roundsFromPayload } from "./rounds/ingest.ts";
import { loadRounds, loadSnapshot, saveRounds } from "./store.ts";

/**
 * Ingest server for Apple Shortcuts.
 *
 * HealthKit is on-device only — Apple exposes no server API, so nothing can
 * read an iPhone's health data remotely. The workable direction is the reverse:
 * a Shortcut running on the phone reads Health locally and POSTs here.
 */

/** Shortcuts payloads are small; anything larger is a mistake or an attack. */
const MAX_BODY_BYTES = 1_000_000;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body, null, 2), {
    status,
    headers: { "content-type": "application/json" },
  });
}

/**
 * Constant-time token comparison. Lengths are compared first because
 * timingSafeEqual throws on a length mismatch, and length alone is not a
 * meaningful secret here.
 */
export function tokenMatches(expected: string, provided: string): boolean {
  const a = Buffer.from(expected, "utf8");
  const b = Buffer.from(provided, "utf8");
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

function bearerFrom(req: Request): string | null {
  const header = req.headers.get("authorization") ?? "";
  const m = /^Bearer\s+(.+)$/i.exec(header.trim());
  // Shortcuts makes custom headers fiddly, so a ?token= query param is
  // accepted too. It is no less safe over HTTPS and far easier to configure.
  if (m) return m[1]!;
  return new URL(req.url).searchParams.get("token");
}

export interface HandlerOptions {
  token: string;
}

export function createHandler(opts: HandlerOptions) {
  return async function handle(req: Request): Promise<Response> {
    const url = new URL(req.url);

    // Liveness is unauthenticated so the phone can confirm reachability
    // before the token is configured. It exposes nothing.
    if (url.pathname === "/health") {
      return json({ ok: true, service: "whoop-18birdies" });
    }

    const provided = bearerFrom(req);
    if (!provided || !tokenMatches(opts.token, provided)) {
      return json({ error: "unauthorized" }, 401);
    }

    if (url.pathname === "/rounds" && req.method === "POST") {
      const raw = await req.text();
      // Measure bytes, not string length: a multi-byte body (accented course
      // names) has fewer UTF-16 code units than bytes and would slip past a
      // .length check that is named and valued in bytes.
      if (Buffer.byteLength(raw, "utf8") > MAX_BODY_BYTES) {
        return json({ error: "payload too large" }, 413);
      }

      let payload: unknown;
      try {
        payload = JSON.parse(raw);
      } catch {
        return json({ error: "body must be JSON" }, 400);
      }

      const rounds = roundsFromPayload(payload);
      if (rounds.length === 0) {
        return json(
          {
            error: "no rounds found in payload",
            hint: "each round needs at least a date (or a start time to derive one)",
          },
          400,
        );
      }

      const all = await saveRounds(rounds);
      return json({
        accepted: rounds.length,
        stored: all.length,
        dates: rounds.map((r) => r.date),
      });
    }

    if (url.pathname === "/readiness" && req.method === "GET") {
      const date = url.searchParams.get("date") ?? new Date().toISOString().slice(0, 10);
      const [rounds, snapshot] = await Promise.all([loadRounds(), loadSnapshot()]);
      const day = indexPhysiology(snapshot).get(date);

      if (!day) {
        return json(
          { date, available: false, message: `No WHOOP data cached for ${date}. Run \`wb sync\`.` },
          404,
        );
      }

      const readiness = computeReadiness(
        day,
        summarise(linkRounds(rounds, snapshot)).correlations,
      );

      // A cached-but-unscored day (WHOOP returns records before scoring
      // finishes) yields score = NaN. Treat that as not-yet-available rather
      // than dropping the literal text "NaN/100" into a phone notification.
      if (!Number.isFinite(readiness.score)) {
        return json(
          {
            date,
            available: false,
            message: `WHOOP data for ${date} is not scored yet. Try again after it syncs.`,
          },
          404,
        );
      }

      const score = Math.round(readiness.score);
      return json({
        date,
        available: true,
        score,
        verdict: readiness.verdict,
        personalised: readiness.personalised,
        advice: readiness.advice,
        // Pre-formatted so a Shortcut can drop it straight into a notification.
        summary: `Golf readiness ${score}/100 (${readiness.verdict}). ${readiness.advice[0] ?? ""}`.trim(),
      });
    }

    return json({ error: "not found" }, 404);
  };
}

export interface ServeOptions extends HandlerOptions {
  port: number;
  hostname: string;
}

export function startServer(opts: ServeOptions): { port: number; stop: () => void } {
  const handle = createHandler(opts);
  const server = Bun.serve({
    port: opts.port,
    hostname: opts.hostname,
    fetch: handle,
  });
  // Bun types `port` as optional (it is unset for unix-socket servers); fall
  // back to the requested port so callers always get a number.
  return { port: server.port ?? opts.port, stop: () => server.stop(true) };
}
