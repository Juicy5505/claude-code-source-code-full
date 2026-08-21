# Agent: tailscale-ingest

**Role:** Report whether Mac ingest (`wb serve`) is reachable on localhost; phone→ingest checklist without recording network identifiers.

**Scope:** Report-only. No secrets. No Tailscale IPs, hostnames, tokens, or Apple team IDs.

**Date:** 2026-08-21

---

## Probe results (localhost only)

| Check | Result |
|-------|--------|
| `lsof -iTCP:8790 -sTCP:LISTEN` | Listening |
| Process name | `wb` |
| Command shape | `wb serve` bound to `127.0.0.1:8790` |
| `curl http://127.0.0.1:8790/` | HTTP `401` (process answering; auth expected) |

**Status:** `REACHABLE_LOCAL`

Interpretation: ingest is running on this Mac and responds on loopback. Phone/LAN reachability via Tailscale is **not** verified here (by design — no Tailscale identifiers recorded).

---

## Phone → ingest checklist

Do **not** paste Tailscale IPs or hostnames into this repo or agent notes.

1. On the Mac, confirm ingest is up: `lsof -iTCP:8790 -sTCP:LISTEN` or open `http://127.0.0.1:8790/` in a local browser (expect auth challenge / 401, not connection refused).
2. Ensure Tailscale is connected on **both** Mac and iPhone (same tailnet).
3. In Tailscale admin (or the Tailscale app), copy **your** Mac’s Tailscale hostname or 100.x address yourself — do not commit it.
4. On the phone (WHOOP Golf / settings), set the ingest base URL to that Tailscale address on port **8790** (scheme/path as the app expects). Prefer hostname over IP if your client supports it.
5. Confirm Mac firewall / `wb serve` bind mode allows Tailscale interface traffic if you need phone access (default `127.0.0.1` bind is **localhost-only** — phone cannot reach it until serve is bound to an interface reachable over Tailscale, or you use a documented tunnel/proxy). Re-check product docs / `wb serve` flags before changing bind.
6. Smoke-test from the phone: hit a health or ingest endpoint; success = app can POST/GET without “connection refused.” A 401 with credentials missing is still “reachable.”
7. Never commit ingest tokens, Tailscale MagicDNS names, or 100.x addresses into git or vault notes that sync publicly.

---

## Agent purpose

Verify local ingest listener presence and document phone connectivity steps without capturing network secrets.

**Agent status:** `DONE`

