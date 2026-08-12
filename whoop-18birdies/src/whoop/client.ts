import { WHOOP, WHOOP_MAX_PAGE_SIZE } from "../config.ts";
import { getAccessToken } from "./oauth.ts";
import type {
  WhoopCycle,
  WhoopPage,
  WhoopProfile,
  WhoopRecovery,
  WhoopSleep,
  WhoopSnapshot,
  WhoopWorkout,
} from "./types.ts";

export interface ClientOptions {
  /** Injected in tests; defaults to the real token store. */
  getToken?: () => Promise<string>;
  fetchImpl?: typeof fetch;
  /** Safety valve so a broken `next_token` cannot loop forever. */
  maxPages?: number;
}

export interface Range {
  start: Date;
  end: Date;
}

const RETRY_STATUSES = new Set([429, 500, 502, 503, 504]);
const MAX_ATTEMPTS = 5;

/**
 * Coerces an id to a string. The types declare ids as opaque strings, but WHOOP
 * returns cycle ids as JSON numbers and the response is cast with `as T`, which
 * does not convert — so without this the runtime value is a number and every
 * string-keyed join silently misses. Applied at the parse boundary.
 */
function idString(id: unknown): string {
  return String(id);
}

export class WhoopClient {
  private readonly getToken: () => Promise<string>;
  private readonly fetchImpl: typeof fetch;
  private readonly maxPages: number;

  constructor(opts: ClientOptions = {}) {
    this.getToken = opts.getToken ?? getAccessToken;
    this.fetchImpl = opts.fetchImpl ?? fetch;
    this.maxPages = opts.maxPages ?? 200;
  }

  private async request<T>(path: string, params: URLSearchParams): Promise<T> {
    const url = `${WHOOP.apiBase}${path}?${params.toString()}`;

    for (let attempt = 1; ; attempt++) {
      const token = await this.getToken();
      const res = await this.fetchImpl(url, {
        headers: { authorization: `Bearer ${token}` },
      });

      if (res.ok) return (await res.json()) as T;

      const body = await res.text().catch(() => "");
      if (!RETRY_STATUSES.has(res.status) || attempt >= MAX_ATTEMPTS) {
        throw new Error(`WHOOP ${path} failed (${res.status}): ${body}`);
      }

      // WHOOP publishes Retry-After on 429; honour it rather than guessing.
      const retryAfter = Number(res.headers.get("retry-after"));
      const delayMs = Number.isFinite(retryAfter) && retryAfter > 0
        ? retryAfter * 1000
        : 2 ** attempt * 250;
      await new Promise((r) => setTimeout(r, delayMs));
    }
  }

  /** Walks every page of a collection endpoint, following `next_token`. */
  private async collect<T>(path: string, range?: Range): Promise<T[]> {
    const out: T[] = [];
    let nextToken: string | undefined;

    for (let page = 0; page < this.maxPages; page++) {
      const params = new URLSearchParams({
        limit: String(WHOOP_MAX_PAGE_SIZE),
      });
      if (range) {
        params.set("start", range.start.toISOString());
        params.set("end", range.end.toISOString());
      }
      if (nextToken) params.set("nextToken", nextToken);

      const body = await this.request<WhoopPage<T>>(path, params);
      out.push(...(body.records ?? []));

      if (!body.next_token) return out;
      nextToken = body.next_token;
    }

    throw new Error(
      `Pagination for ${path} exceeded ${this.maxPages} pages — aborting to avoid an infinite loop.`,
    );
  }

  profile(): Promise<WhoopProfile> {
    return this.request<WhoopProfile>("/v2/user/profile/basic", new URLSearchParams());
  }

  async cycles(range?: Range): Promise<WhoopCycle[]> {
    const rows = await this.collect<WhoopCycle>("/v2/cycle", range);
    return rows.map((c) => ({ ...c, id: idString(c.id) }));
  }

  async recoveries(range?: Range): Promise<WhoopRecovery[]> {
    const rows = await this.collect<WhoopRecovery>("/v2/recovery", range);
    // cycle_id and sleep_id are the join keys; coerce both so a numeric id from
    // WHOOP matches the string-keyed cycles/sleeps despite the `as T` cast.
    return rows.map((r) => ({
      ...r,
      cycle_id: idString(r.cycle_id),
      sleep_id: idString(r.sleep_id),
    }));
  }

  async sleeps(range?: Range): Promise<WhoopSleep[]> {
    const rows = await this.collect<WhoopSleep>("/v2/activity/sleep", range);
    return rows.map((s) => ({ ...s, id: idString(s.id) }));
  }

  async workouts(range?: Range): Promise<WhoopWorkout[]> {
    const rows = await this.collect<WhoopWorkout>("/v2/activity/workout", range);
    return rows.map((w) => ({ ...w, id: idString(w.id) }));
  }

  /**
   * Pulls everything needed for a correlation report in one shot. Profile
   * failures are tolerated because `read:profile` may not have been granted and
   * nothing downstream depends on it.
   */
  async snapshot(range: Range): Promise<WhoopSnapshot> {
    const [cycles, recoveries, sleeps, workouts] = await Promise.all([
      this.cycles(range),
      this.recoveries(range),
      this.sleeps(range),
      this.workouts(range),
    ]);
    const profile = await this.profile().catch(() => undefined);
    return {
      fetchedAt: new Date().toISOString(),
      profile,
      cycles,
      recoveries,
      sleeps,
      workouts,
    };
  }
}
