import { randomBytes } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { createServer } from "node:http";
import { dirname } from "node:path";
import {
  DEFAULT_SCOPES,
  WHOOP,
  loadAppConfig,
  paths,
  type OAuthAppConfig,
} from "../config.ts";

export interface TokenSet {
  access_token: string;
  refresh_token?: string;
  /** Absolute epoch ms. Derived from `expires_in` at grant time. */
  expires_at: number;
  scope?: string;
}

interface TokenResponse {
  access_token: string;
  refresh_token?: string;
  expires_in: number;
  scope?: string;
}

/** Refresh this long before actual expiry so in-flight requests don't race it. */
const EXPIRY_SKEW_MS = 60_000;

export async function saveTokens(tokens: TokenSet): Promise<void> {
  const file = paths.tokens();
  await mkdir(dirname(file), { recursive: true });
  // Tokens grant read access to health data; keep them owner-only.
  await writeFile(file, JSON.stringify(tokens, null, 2), { mode: 0o600 });
}

export async function loadTokens(): Promise<TokenSet | null> {
  try {
    return JSON.parse(await readFile(paths.tokens(), "utf8")) as TokenSet;
  } catch {
    return null;
  }
}

function toTokenSet(raw: TokenResponse): TokenSet {
  return {
    access_token: raw.access_token,
    refresh_token: raw.refresh_token,
    expires_at: Date.now() + raw.expires_in * 1000,
    scope: raw.scope,
  };
}

async function postToken(
  app: OAuthAppConfig,
  body: Record<string, string>,
): Promise<TokenSet> {
  const res = await fetch(WHOOP.tokenUrl, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: app.clientId,
      client_secret: app.clientSecret,
      ...body,
    }),
  });
  const text = await res.text();
  if (!res.ok) {
    throw new Error(`WHOOP token request failed (${res.status}): ${text}`);
  }
  return toTokenSet(JSON.parse(text) as TokenResponse);
}

/**
 * Runs the one-time authorization-code flow. Spins up a loopback server on the
 * registered redirect URI, prints the consent URL, and blocks until WHOOP
 * redirects back.
 */
export async function authorize(
  openUrl: (url: string) => void = (url) =>
    console.log(`\nOpen this URL to authorize WHOOP:\n\n${url}\n`),
): Promise<TokenSet> {
  const app = loadAppConfig();
  const redirect = new URL(app.redirectUri);
  // WHOOP rejects state values under 8 characters, which is easy to trip with
  // a short nonce and produces an opaque error at the consent screen.
  const state = randomBytes(16).toString("hex");

  const authUrl = new URL(WHOOP.authorizeUrl);
  authUrl.searchParams.set("client_id", app.clientId);
  authUrl.searchParams.set("redirect_uri", app.redirectUri);
  authUrl.searchParams.set("response_type", "code");
  authUrl.searchParams.set("scope", DEFAULT_SCOPES.join(" "));
  authUrl.searchParams.set("state", state);

  const code = await new Promise<string>((resolve, reject) => {
    const server = createServer((req, res) => {
      const url = new URL(req.url ?? "/", `http://${redirect.host}`);
      if (url.pathname !== redirect.pathname) {
        res.writeHead(404).end("Not found");
        return;
      }
      const err = url.searchParams.get("error");
      const returnedState = url.searchParams.get("state");
      const returnedCode = url.searchParams.get("code");

      const fail = (message: string) => {
        res.writeHead(400, { "content-type": "text/plain" }).end(message);
        server.close();
        reject(new Error(message));
      };

      if (err) return fail(`WHOOP returned an error: ${err}`);
      if (returnedState !== state) return fail("State mismatch — aborting.");
      if (!returnedCode) return fail("No authorization code in callback.");

      res
        .writeHead(200, { "content-type": "text/html" })
        .end("<h2>WHOOP linked.</h2><p>You can close this tab.</p>");
      server.close();
      resolve(returnedCode);
    });
    server.on("error", reject);
    server.listen(Number(redirect.port || 80), redirect.hostname, () => {
      openUrl(authUrl.toString());
    });
  });

  const tokens = await postToken(app, {
    grant_type: "authorization_code",
    code,
    redirect_uri: app.redirectUri,
  });
  await saveTokens(tokens);
  return tokens;
}

export async function refresh(tokens: TokenSet): Promise<TokenSet> {
  if (!tokens.refresh_token) {
    throw new Error(
      "No refresh token stored. Re-run `wb login` — the `offline` scope is required to get one.",
    );
  }
  const app = loadAppConfig();
  const next = await postToken(app, {
    grant_type: "refresh_token",
    refresh_token: tokens.refresh_token,
    scope: "offline",
  });
  // WHOOP does not always return a new refresh token; keep the old one so the
  // grant survives instead of silently becoming non-renewable.
  const merged: TokenSet = {
    ...next,
    refresh_token: next.refresh_token ?? tokens.refresh_token,
  };
  await saveTokens(merged);
  return merged;
}

/** Returns a valid access token, refreshing on the fly when it is near expiry. */
export async function getAccessToken(): Promise<string> {
  const tokens = await loadTokens();
  if (!tokens) {
    throw new Error("Not linked to WHOOP yet. Run `wb login` first.");
  }
  if (Date.now() < tokens.expires_at - EXPIRY_SKEW_MS) {
    return tokens.access_token;
  }
  return (await refresh(tokens)).access_token;
}
