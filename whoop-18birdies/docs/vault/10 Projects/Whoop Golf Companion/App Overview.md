# App Overview — WHOOP Golf (D19 both-required)

Sanitized continuous overview for Obsidian / graphify. **No** tokens, UDIDs, Tailscale IPs, team IDs, or raw HR streams.

Updated: 2026-08-21 (vault-obsidian-graphify — dual maximize + both-required + graphify cadence)

## Product posture (dual maximize)

| Device | Role |
|---|---|
| Apple Watch Series 5 (trail **right**) | Live path score + explanation, tempo/improver, HR workout, on-wrist yards / hole / club / ball-start |
| WHOOP 5.0 | Delayed swing import / enrich, readiness / recovery / day strain; never live `TOGGLE_IMU` Arming |
| iPhone | GPS swing-to-swing shot yards, stroke journal, Overview fusion glass, dual-gate preflight |

One icon: **WHOOP Golf** · `com.alex.whoopgolf` · `whoop-18birdies/apple/WhoopGolf.xcodeproj`

## Admission (both-required)

New rounds **require both** wearables proven before start (`DualWearableRequirement`):

1. Apple Watch live-capture proven
2. WHOOP swing source proven (delayed import path — not live IMU)

Watch-only / WHOOP-only / manual remain diagnostic plan modes only — **not** startable products. Existing drafts on disk stay readable. Decision detail: [[D19-Hybrid-maximize-both]].

## Tracking glass (per verified stroke)

- Club (golfer-selected)
- Body-relative path score + explanation
- Derived ball-start tendency (not launch monitor)
- Attack/delivery feel (coaching)
- Swing-to-swing GPS yards
- Hybrid provenance (Watch identity + WHOOP enrich, no double-count)

## In-app Overview tab

Surfaces dual-gate admission status, readiness hero, last-round stroke count / avg path score / swing-to-swing yards, Watch+WHOOP contribution pills, consistency streak, and a copyable path to this note.

## Round health buckets (fill after real rounds)

| Bucket | Latest | Notes |
|---|---|---|
| Dual admission | — | Both Watch + WHOOP proven at round start |
| Readiness score | — | From cached WHOOP cloud via private bridge |
| Recovery % | — | Day physiology |
| Day strain | — | Not live IMU |
| Last round strokes | — | Verified journal rows |
| Avg path score | — | Body-relative 0…100 |
| Measured shot yards (sum) | — | Phone GPS between verified swings |
| Miss pattern | — | Dominant path class share |
| Tempo consistency | — | CV / sparkline on Trends |

## Graphify update cadence

Canonical cadence for the D19 control loop (D16 history retained; do not rewrite):

| When | Where | Command |
|---|---|---|
| After each feature slice / agent wave | `whoop-18birdies/apple` | `graphify update .` |
| If Watch companion sources touched | Watch tree under apple/ (or watch kit if touched) | `graphify update .` |
| When Obsidian vault is mounted | This vault root | `graphify update` (or vault-scoped update) |
| End of session | Vault Decisions / Cursor memory | Append why-note; keep **D19** active — do not rewrite D15 / D18 |

Notes:

- Prefer local `graphify update` (no API cost) over full rebuilds.
- Skip expanding STATUS.md graphify chatter when this App Overview + D19 note already record the checkpoint.
- Never paste secrets, device IDs, LAN IPs, or raw HR samples into graph nodes or vault notes.

## Install gate

- Phone: Personal Team signed reinstall as needed
- Physical Watch install: **only after OS update is confirmed done**
