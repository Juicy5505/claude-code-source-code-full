# App Overview — WHOOP Golf (D19)

Sanitized continuous overview for Obsidian / graphify. **No** tokens, UDIDs, Tailscale IPs, team IDs, or raw HR streams.

Updated: 2026-08-21

## Product posture

| Device | Role |
|---|---|
| Apple Watch Series 5 (trail **right**) | Live path score + explanation, tempo/improver, HR workout, on-wrist yards |
| WHOOP 5.0 | Delayed swing import, readiness / recovery / day strain; never live `TOGGLE_IMU` Arming |
| iPhone | GPS swing-to-swing shot yards, stroke journal, Overview fusion glass |

One icon: **WHOOP Golf** · `com.alex.whoopgolf` · `whoop-18birdies/apple/WhoopGolf.xcodeproj`

## In-app Overview tab

Surfaces readiness hero, last-round stroke count / avg path score / swing-to-swing yards, Watch+WHOOP contribution pills, consistency streak, and a copyable path to this note.

## Round health buckets (fill after real rounds)

| Bucket | Latest | Notes |
|---|---|---|
| Readiness score | — | From cached WHOOP cloud via private bridge |
| Recovery % | — | Day physiology |
| Day strain | — | Not live IMU |
| Last round strokes | — | Verified journal rows |
| Avg path score | — | Body-relative 0…100 |
| Measured shot yards (sum) | — | Phone GPS between verified swings |
| Miss pattern | — | Dominant path class share |
| Tempo consistency | — | CV / sparkline on Trends |

## Graphify checkpoints

After each feature slice:

1. `graphify update .` in `whoop-18birdies/apple` (and watch app if touched)
2. `graphify update` on the Obsidian vault when mounted
3. Append session why-note; do not rewrite D15 / D18 history — keep **D19** as the hybrid maximize-both decision

## Install gate

- Phone: Personal Team signed reinstall as needed
- Physical Watch install: **only after OS update is confirmed done**
