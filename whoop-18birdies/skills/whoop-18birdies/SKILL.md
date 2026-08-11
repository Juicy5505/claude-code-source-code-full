---
name: whoop-18birdies
description: Link WHOOP recovery, sleep and strain data to 18Birdies golf rounds. Use when the user asks to connect WHOOP to 18Birdies, sync golf rounds with WHOOP, check golf readiness before a round, find out how recovery and sleep affect their scoring, or get golf/Apple Health data off their iPhone.
---

# WHOOP × 18Birdies

Connects WHOOP physiology to golf scoring. Before doing anything, know what is
and is not possible — getting this wrong wastes the user's time chasing an
integration that does not exist.

## What actually connects

**18Birdies has no public API.** There is no self-serve developer program, no
OAuth, and no CSV/spreadsheet export of round data. API access is
partnership-only. Do not go looking for an endpoint or suggest scraping the
app's private API.

**WHOOP has a full public API** (OAuth2, read-only) plus a two-way Apple Health
integration.

That leaves two real paths, and they do different jobs:

| Path | Direction | What it gets you | Needs code? |
|---|---|---|---|
| Apple Health bridge | 18Birdies → WHOOP | The round shows up in WHOOP as an activity with strain | No — phone settings |
| This toolkit | WHOOP → analysis | Recovery/sleep/strain correlated with your scoring | Yes — `wb` CLI |

Neither path pushes WHOOP data *into* the 18Birdies app. That is not possible
without a partnership. If the user wants recovery numbers visible next to their
scorecard, say so plainly and offer the report instead.

## Path 1 — the on-phone link (do this first)

This is the answer to "link the WHOOP app on my phone to 18Birdies". It is
pure configuration; walk the user through it rather than writing code.

1. **18Birdies → Apple Health.** Start a round to reach the GPS screen on the
   watch, long-press for the options menu, tap Settings, and set the
   **Watch Health Kit** toggle to **On**.
2. **WHOOP → Apple Health.** In WHOOP: **More → App Settings → Integrations →
   Apple Health → Connect**, and allow workouts, heart rate and sleep.
3. Play a round. WHOOP reads the activity's start/end window out of Apple
   Health and scores strain against its own continuous heart-rate data, so the
   round lands in WHOOP without the WHOOP app needing to know about golf.

**Caveat worth stating up front:** 18Birdies does not classify its activity as
an `HKWorkoutActivityTypeGolf` workout. The time window transfers, so strain is
computed correctly, but the activity may show up in WHOOP under a generic
classification rather than as golf. The user can re-label it in WHOOP.

## Path 2 — the toolkit

Located at `whoop-18birdies/`. Bun, no runtime dependencies.

### One-time setup

The user creates an app at developer.whoop.com (My Apps → Create), then:

```bash
export WHOOP_CLIENT_ID=...
export WHOOP_CLIENT_SECRET=...
export WHOOP_REDIRECT_URI=http://localhost:8788/callback   # must match the app exactly
cd whoop-18birdies && bun src/cli.ts login
```

`login` starts a loopback server and prints a consent URL. Tokens are written
to `~/.whoop-18birdies/tokens.json` with mode 0600 and auto-refresh.

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
bun src/cli.ts serve [--port N]            # ingest server for the iPhone Shortcut
```

### Getting rounds in

Because 18Birdies will not export, rounds arrive one of two ways:

- **CSV** (`import-csv`) — the only source that carries strokes, par and putts,
  so it is the only one that makes `report` useful. Headers are alias-matched;
  `date` is the sole requirement. Run `template` to show the format.
- **Apple Health export** (`import-health`) — Health app → profile → Export All
  Health Data. Gets dates, tee times and duration automatically, but Apple
  Health has no scorecard, so these rounds have no score until the user adds
  one via CSV. The two merge on a stable id, and the richer record wins.

If the user wants to backfill scores, offer to transcribe them from 18Birdies
screenshots into the CSV template — that is usually faster than typing.

## If the user asks you to read their iPhone directly

Say plainly that this is not possible for anyone, and why: **HealthKit is
on-device only.** Apple exposes no cloud API for it, there is no Apple Health /
HealthKit / iCloud MCP connector (verified against the connector registry), and
no amount of permissions changes that. Do not go hunting for a server that
reads it, and do not imply you have connected to their phone.

Then offer the direction that does work — **the phone pushes data out**:

1. `bun src/cli.ts serve` on their machine. It prints LAN URLs and a bearer
   token, binds `0.0.0.0`, and exposes `/health`, `POST /rounds`, and
   `GET /readiness`.
2. An Apple Shortcut on the iPhone reads Health locally and POSTs to `/rounds`;
   a second Shortcut GETs `/readiness` and shows a notification. Full recipes,
   including automation triggers, are in `IPHONE.md` — walk them through it
   rather than improvising the steps.

Two things to keep straight:

- WHOOP needs no phone involvement at all; the toolkit pulls it from WHOOP's
  cloud API. **The phone's only job is supplying golf rounds.**
- Shortcuts action labels drift between iOS versions and Apple's docs were
  unreachable when `IPHONE.md` was written. The JSON shapes are right; if a
  label doesn't match, tell them to find the nearest equivalent. The server is
  deliberately forgiving about key names and string-typed numbers.

If they'd rather not run a server, `import-health` on an Apple Health export
zip does a one-off backfill with no server at all.

## Interpreting the report

`report` correlates six metrics against strokes-to-par (9-hole rounds are
doubled to normalise). **Negative r means more of that metric goes with a lower,
better score.**

Be honest about the statistics:

- Under ~10 usable rounds, the numbers are directional only. Say so.
- Golf scoring is dominated by course difficulty, weather and playing partners.
  A physiological effect has to be large to surface above that noise.
- `p` is a two-sided p-value on the Pearson r. Do not describe a p ≥ 0.05
  result as a finding.
- Correlation here is not causation — a well-rested week may also be a week
  the user happened to play their home course.

## Readiness

`readiness` is a **heuristic this toolkit defines, not a WHOOP metric.** WHOOP
publishes no golf readiness score. It blends recovery (50%), sleep (30%) and
prior-day strain (20%), renormalising when an input is missing. Once the user
has 8+ scored rounds, the weights shift toward whichever metrics actually track
their scoring, and the output marks itself as tuned.

Never present the readiness number as coming from WHOOP.

## Things to avoid

- Do not claim a two-way sync exists.
- Do not suggest automating the 18Birdies app through its private API or by
  scripting the UI.
- Do not fabricate WHOOP endpoint paths. If a call 404s, the API base and
  OAuth URLs are overridable via `WHOOP_API_BASE`, `WHOOP_AUTHORIZE_URL` and
  `WHOOP_TOKEN_URL` — check the live docs and override rather than guessing.
- Do not report a correlation over fewer than 3 rounds; the code already
  suppresses these, so if a metric is missing from the table, that is why.
