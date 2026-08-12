import { homedir } from "node:os";
import { join } from "node:path";

/**
 * WHOOP API endpoints.
 *
 * These are overridable via env because developer.whoop.com was unreachable
 * from the build environment and WHOOP has moved paths before (the v1 -> v2
 * migration changed both the path prefix and the ID types). If a call 404s,
 * check the live docs and override rather than editing code.
 */
export const WHOOP = {
  apiBase: process.env.WHOOP_API_BASE ?? "https://api.prod.whoop.com/developer",
  authorizeUrl:
    process.env.WHOOP_AUTHORIZE_URL ??
    "https://api.prod.whoop.com/oauth/oauth2/auth",
  tokenUrl:
    process.env.WHOOP_TOKEN_URL ??
    "https://api.prod.whoop.com/oauth/oauth2/token",
} as const;

/**
 * WHOOP caps `limit` at 25 on collection endpoints and rejects larger values
 * outright, so this is a hard ceiling rather than a tuning knob.
 */
export const WHOOP_MAX_PAGE_SIZE = 25;

export const DEFAULT_SCOPES = [
  "offline",
  "read:profile",
  "read:body_measurement",
  "read:cycles",
  "read:sleep",
  "read:recovery",
  "read:workout",
] as const;

export function dataDir(): string {
  return process.env.WB_DATA_DIR ?? join(homedir(), ".whoop-18birdies");
}

export const paths = {
  tokens: () => join(dataDir(), "tokens.json"),
  whoopCache: () => join(dataDir(), "whoop-cache.json"),
  rounds: () => join(dataDir(), "rounds.json"),
  /** Watch swing sessions land here, one file per session. */
  watchSessions: () => join(dataDir(), "watch-sessions"),
  watchSession: (name: string) => join(dataDir(), "watch-sessions", `${name}.json`),
};

export interface OAuthAppConfig {
  clientId: string;
  clientSecret: string;
  redirectUri: string;
}

/**
 * Reads the OAuth app credentials created at developer.whoop.com. The redirect
 * URI must match the one registered there exactly, port included.
 */
export function loadAppConfig(): OAuthAppConfig {
  const clientId = process.env.WHOOP_CLIENT_ID;
  const clientSecret = process.env.WHOOP_CLIENT_SECRET;
  if (!clientId || !clientSecret) {
    throw new Error(
      "Missing WHOOP_CLIENT_ID / WHOOP_CLIENT_SECRET.\n" +
        "Create an app at https://developer.whoop.com (My Apps -> Create), then export both.\n" +
        "Register the redirect URI below in that app or the login will be rejected.",
    );
  }
  return {
    clientId,
    clientSecret,
    redirectUri:
      process.env.WHOOP_REDIRECT_URI ?? "http://localhost:8788/callback",
  };
}
