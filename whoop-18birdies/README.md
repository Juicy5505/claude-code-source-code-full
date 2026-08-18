# whoop-18birdies

Golf tracking built around a WHOOP strap and an iPhone: yardages, swing tempo,
and whether your body being under-recovered actually shows up in your scoring.

> ### → [START-HERE.md](START-HERE.md)
>
> If you have a WHOOP and an iPhone and want numbers today, read that instead.
> It is the short path: three ways to track a round, ordered by how little you
> have to wear, starting with one that needs nothing but the strap.

The rest of this file is the reference — every command, the API details, and the
constraints that shaped the design.

## What's actually possible

Worth reading before you start, because one half of this is a settings change
and the other half is code.

**18Birdies has no public API.** No developer program, no OAuth, and no
CSV/spreadsheet export of round data — their support docs confirm playing data
cannot be exported to a spreadsheet. API access is partnership-only.

**WHOOP has a full public REST API** (OAuth2, read-only) and a two-way Apple
Health integration.

So there are two links, doing two different jobs:

| Path | Direction | What you get | Code? |
|---|---|---|---|
| Apple Health bridge | 18Birdies → WHOOP | Your round appears in WHOOP with strain | No |
| This toolkit | WHOOP → analysis | Recovery/sleep/strain vs. your scoring | Yes |

Neither pushes WHOOP data *into* the 18Birdies app. That needs a partnership
with 18Birdies, not a client.

**Running it from an iPhone?** See [IPHONE.md](IPHONE.md). Short version:
nothing can read your iPhone's Health data remotely — HealthKit is on-device
only, with no cloud API — so the phone pushes data out instead, via an Apple
Shortcut hitting `wb serve`. No Mac or Xcode needed.

---

## Path 1 — the on-phone link

No code. This is what makes your golf rounds show up in WHOOP.

1. **18Birdies → Apple Health.** Start a round to reach the GPS screen on the
   watch, long-press for the options menu, tap **Settings**, and set
   **Watch Health Kit** to **On**.
2. **WHOOP → Apple Health.** In WHOOP: **More → App Settings → Integrations →
   Apple Health → Connect**. Allow workouts, heart rate and sleep.
3. Play. WHOOP takes the activity's start/end window from Apple Health and
   scores strain against its own continuous heart-rate data.

**Caveat:** 18Birdies does not tag its activity as an
`HKWorkoutActivityTypeGolf` workout. The time window transfers and strain is
computed correctly, but the activity may land in WHOOP under a generic
classification. Re-label it in WHOOP if it matters to you.

---

## Path 2 — the toolkit

Bun, no runtime dependencies.

### Setup

Create an app at [developer.whoop.com](https://developer.whoop.com) (My Apps →
Create). Register the redirect URI below in that app — it must match exactly,
port included.

```bash
export WHOOP_CLIENT_ID=...
export WHOOP_CLIENT_SECRET=...
export WHOOP_REDIRECT_URI=http://localhost:8788/callback

cd whoop-18birdies
bun src/cli.ts login
```

`login` starts a loopback server, prints a consent URL, and stores tokens in
`~/.whoop-18birdies/tokens.json` (mode 0600). They refresh automatically; the
`offline` scope is requested so the refresh token exists.

### Commands

```bash
bun src/cli.ts status                      # link state, cached data, round count
bun src/cli.ts sync --days 180             # pull cycles, recovery, sleep, workouts
bun src/cli.ts template                    # print the round CSV template
bun src/cli.ts import-csv rounds.csv       # import scorecards
bun src/cli.ts import-health export.xml    # import golf rounds from an Apple Health export
bun src/cli.ts rounds                      # list stored rounds
bun src/cli.ts report                      # correlate WHOOP metrics against scoring
bun src/cli.ts readiness [YYYY-MM-DD]      # golf readiness for a date
bun src/cli.ts golf [YYYY-MM-DD|--list]    # the round as WHOOP alone recorded it
bun src/cli.ts serve [--port N]            # ingest server for the phone
```

`golf` is the one that needs no scorecard and no phone: WHOOP detects the round
itself, and this joins it to the recovery, sleep and day strain around it.
`golf --list` prints every activity name in your data, for when WHOOP files a
round as something other than Golf.

### Getting rounds in

18Birdies won't export, so rounds come from one of two places:

**CSV** — the only source carrying strokes, par and putts, so it's the only one
that makes `report` useful. Headers are alias-matched (`Gross`, `Total Putts`,
`Course Par`, `FIR`, `GIR` all work); `date` is the only requirement.

```csv
date,course,holes,par,score,putts,fairways hit,fairways possible,gir,start time,notes
2026-05-04,Torrey Pines South,18,72,86,34,6,14,5,2026-05-04T08:10:00-07:00,windy back nine
```

**Apple Health export** — Health app → profile → **Export All Health Data**.
Picks up golf-typed workouts *and* anything sourced from 18Birdies (needed,
since 18Birdies doesn't classify its activity as golf). Gets dates, tee times
and duration; Apple Health has no scorecard, so these rounds carry no score
until you add one by CSV. Records merge on a stable id and the richer one wins,
so importing both sources is safe and re-importing is idempotent.

The parser streams the file — `export.xml` is routinely hundreds of megabytes.

### Example report

```
Correlation with strokes-to-par (negative = more of it, lower score):

  metric                 n     r      rho     p       mean
  Resting HR            10    0.93   0.91  0.000  58.6bpm
  Recovery %            10   -0.93  -0.91  0.000  48.0%
  HRV (RMSSD)           10   -0.93  -0.91  0.000  49.0ms
  Sleep duration        10   -0.93  -0.91  0.000  6.1h
  Prior-day strain       9   -0.31  -0.34  0.413  11.6
```

Nine-hole rounds are doubled so they sit in the same regression as 18s. `p` is
a two-sided p-value on the Pearson r, computed from the t distribution via a
regularised incomplete beta.

**Read these carefully.** Golf scoring is dominated by course difficulty,
weather and who you're playing with. Under ~10 usable rounds the numbers are
directional only, and the report says so. A metric needs at least 3 rounds with
both a score and WHOOP data to appear at all.

### Ingest server

`serve` accepts rounds pushed from an Apple Shortcut on your iPhone and can
hand readiness back for a notification:

| Route | Method | Purpose |
|---|---|---|
| `/health` | GET | Reachability. No auth. |
| `/rounds` | POST | Round JSON. Forgiving about key names and string numbers. |
| `/readiness?date=` | GET | Readiness, preformatted for a notification. |

Auth is a bearer token (`WB_INGEST_TOKEN`, or one generated per run), accepted
as either an `Authorization` header or `?token=` — the latter because custom
headers in Shortcuts are fiddly. It binds `0.0.0.0` over plain HTTP, which is
fine on your own LAN and not fine exposed to the internet; use a TLS tunnel if
you need it off-network. Full Shortcut recipes are in [IPHONE.md](IPHONE.md).

### Readiness

```
Golf readiness — 2026-08-11

  82/100  (prime)
  weights: tuned to your round history

  Recovery    82/100  ×0.53  82% · HRV 66 ms
  Sleep      100/100  ×0.32  8.3 h asleep
  Freshness   43/100  ×0.15  prior-day strain 12.0

  • Green light — this is a day to be aggressive off the tee.
```

This is a heuristic **defined here, not by WHOOP** — WHOOP publishes no golf
readiness score. It blends recovery (50%), sleep (30%) and prior-day strain
(20%), renormalising when an input is missing. After 8+ scored rounds the
weights shift toward whatever actually tracks your scoring, and the output
marks itself as tuned.

---

## Claude skill

`skills/whoop-18birdies/SKILL.md` teaches Claude to drive all of the above —
including the constraints, so it won't go hunting for an 18Birdies API that
isn't there. Point Claude at this directory, or copy the skill into
`~/.claude/skills/`.

## Development

```bash
bun test                      # 74 tests
bun run typecheck
```

Everything network-facing is injectable (`fetchImpl`, `getToken`), so the
client is tested against mocked responses — pagination, 429 retry with
`Retry-After`, non-retryable 401s, and runaway-pagination guards included.

## Notes on the WHOOP API

Endpoint constants live in `src/config.ts` and are all overridable
(`WHOOP_API_BASE`, `WHOOP_AUTHORIZE_URL`, `WHOOP_TOKEN_URL`). They target v2:
`/v2/cycle`, `/v2/recovery`, `/v2/activity/sleep`, `/v2/activity/workout`,
`/v2/user/profile/basic`. WHOOP caps `limit` at 25 and paginates with
`next_token`.

developer.whoop.com was unreachable from the environment this was built in, so
if a call 404s, check the live docs and override rather than editing code —
WHOOP moved both paths and ID types in the v1→v2 migration and could again.
IDs are handled as opaque strings throughout for that reason.

## Sources

- [WHOOP v1→v2 migration guide](https://developer.whoop.com/docs/developing/v1-v2-migration/)
- [WHOOP API docs](https://developer.whoop.com/api/)
- [WHOOP Apple Health integration](https://support.whoop.com/hc/en-us/articles/4413142119195-Apple-Health-Integration)
- [18Birdies: Apple Watch / Watch Health Kit toggle](https://help.18birdies.com/article/272-apple-watch)
- [18Birdies: can I export to CSV or Excel?](https://help.18birdies.com/article/643-can-i-export-18birdies-data-to-a-csv-or-excel-spreadsheet)
