# App Overview — WHOOP Golf (D19 both-required)

Sanitized continuous overview for Obsidian / graphify. **No** tokens, UDIDs, Tailscale IPs, team IDs, or raw HR streams.

Updated: 2026-08-21 (agent civilization close)

## Product posture

| Device | Role |
|---|---|
| Apple Watch Series 5 (trail **right**) | Live path score + explanation, tempo/improver, HR workout, on-wrist yards/club/ball-start |
| WHOOP 5.0 | Delayed swing enrich, readiness / recovery / day strain; never live `TOGGLE_IMU` Arming |
| iPhone | GPS swing-to-swing shot yards, stroke journal, dual-gate Overview |

**Admission:** new rounds require **both** Watch live-capture and WHOOP swing source (`DualWearableRequirement`). Single-wearable starts are blocked.

One icon: **WHOOP Golf** · `com.alex.whoopgolf`

## Tracking glass (per verified stroke)

- Club (golfer-selected)
- Body-relative path score + explanation
- Derived ball-start tendency (not launch monitor)
- Attack/delivery feel (coaching)
- Swing-to-swing GPS yards
- Hybrid provenance (Watch identity + WHOOP enrich, no double-count)

## Round health buckets (fill after real rounds)

| Bucket | Latest | Notes |
|---|---|---|
| Readiness score | — | Cached WHOOP cloud via private bridge |
| Recovery % | — | Day physiology |
| Day strain | — | Not live IMU |
| Last round strokes | — | Verified journal |
| Avg path score | — | 0…100 body-relative |
| Measured shot yards | — | Phone GPS between swings |
| Miss pattern | — | Dominant path class |
| Tempo consistency | — | Trends sparkline |

## Graphify checkpoints

1. After each feature slice: `graphify update .` in `whoop-18birdies/apple` when installed
2. Vault: `graphify update` when Obsidian vault mounted
3. Append session why-note; keep **D19** (do not rewrite D15/D18)

## Install gate

- Phone: Personal Team signed reinstall as needed
- Physical Watch install: **only after OS update confirmed**
