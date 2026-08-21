# tailscale-ingest

**Status:** done — LAN bind ok

## Outcome
- LaunchAgent `com.alex.whoop-golf-bridge` now starts `wb serve` with all-interfaces bind + `--allow-insecure-lan` (was loopback-only).
- Workspace `whoop-18birdies/src/cli.ts` gained `--hostname` / `--allow-insecure-lan` parity with the installed binary (default remains loopback; LAN requires the explicit flag).
- `/health` and `/healthz` respond on the local port; listener is not loopback-only.

## Notes
- Do not log tokens, hostnames, or IPs into the vault.
- Xcode / apple projects untouched.
- Phone/sidecar should use Tailscale or LAN URL + matching ingest token (see SETUP-MAC).
