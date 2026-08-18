#!/usr/bin/env bun
import { randomBytes } from "node:crypto";
import { readFile } from "node:fs/promises";
import { networkInterfaces } from "node:os";
import { dataDir } from "./config.ts";
import { startServer } from "./server.ts";
import { CSV_TEMPLATE, roundsFromCsv } from "./rounds/csv.ts";
import { roundsFromAppleHealthExport } from "./rounds/appleHealth.ts";
import { scoreToPar } from "./rounds/types.ts";
import {
  buildGolfRound,
  formatGolfRound,
  golfWorkouts,
  sportNames,
  whoopCoverage,
} from "./link/golfRound.ts";
import {
  indexPhysiology,
  linkRounds,
  summarise,
  whoopLocalDate,
} from "./link/correlate.ts";
import { computeReadiness } from "./link/readiness.ts";
import { loadRounds, loadSnapshot, saveRounds, saveSnapshot } from "./store.ts";
import { WhoopClient } from "./whoop/client.ts";
import { authorize, loadTokens } from "./whoop/oauth.ts";

const USAGE = `wb — link WHOOP physiology to 18Birdies golf rounds

  wb login                       Authorize WHOOP (one time, opens a consent URL)
  wb status                      Show link state, cached data, and round count
  wb sync [--days N]             Pull WHOOP cycles/recovery/sleep/workouts (default 180)
  wb import-csv <file>           Import 18Birdies rounds from a CSV scorecard
  wb import-health <export.xml>  Import golf rounds from an Apple Health export
  wb template                    Print the round CSV template
  wb rounds                      List stored rounds
  wb report                      Correlate WHOOP metrics against scoring
  wb readiness [YYYY-MM-DD]      Golf readiness for a date (default: today)
  wb golf [YYYY-MM-DD|--list]    The round as WHOOP alone recorded it
  wb serve [--port N]            Ingest server for the iPhone Shortcut

Setup: create an app at developer.whoop.com, then export
  WHOOP_CLIENT_ID, WHOOP_CLIENT_SECRET
  WHOOP_REDIRECT_URI (default http://localhost:8788/callback — must match the app)
`;

function fmt(n: number, digits = 2): string {
  return Number.isFinite(n) ? n.toFixed(digits) : "n/a";
}

function today(): string {
  return new Date().toISOString().slice(0, 10);
}

function flagValue(args: string[], name: string): string | undefined {
  const i = args.indexOf(name);
  return i === -1 ? undefined : args[i + 1];
}

async function cmdLogin(): Promise<void> {
  const tokens = await authorize();
  console.log(
    `WHOOP linked. Token expires ${new Date(tokens.expires_at).toLocaleString()}.`,
  );
  console.log(`Credentials stored in ${dataDir()} (owner-readable only).`);
}

async function cmdStatus(): Promise<void> {
  const tokens = await loadTokens();
  const snapshot = await loadSnapshot();
  const rounds = await loadRounds();

  console.log(`Data directory : ${dataDir()}`);
  console.log(
    `WHOOP link     : ${
      tokens
        ? `linked (token ${Date.now() < tokens.expires_at ? "valid" : "expired, will refresh"})`
        : "not linked — run `wb login`"
    }`,
  );
  console.log(
    `WHOOP cache    : ${snapshot.cycles.length} cycles, ${snapshot.recoveries.length} recoveries, ` +
      `${snapshot.sleeps.length} sleeps, ${snapshot.workouts.length} workouts` +
      (snapshot.cycles.length ? ` (fetched ${snapshot.fetchedAt})` : ""),
  );
  console.log(`Rounds stored  : ${rounds.length}`);

  const scored = rounds.filter((r) => scoreToPar(r) != null).length;
  if (rounds.length > 0 && scored < rounds.length) {
    console.log(
      `\n${rounds.length - scored} round(s) have no score/par and cannot enter the correlation.`,
    );
  }
}

async function cmdSync(args: string[]): Promise<void> {
  const days = Number(flagValue(args, "--days") ?? 180);
  if (!Number.isFinite(days) || days <= 0) {
    throw new Error("--days must be a positive number");
  }
  const end = new Date();
  const start = new Date(end.getTime() - days * 86_400_000);

  console.log(`Fetching WHOOP data for the last ${days} days…`);
  const snapshot = await new WhoopClient().snapshot({ start, end });
  await saveSnapshot(snapshot);
  console.log(
    `Cached ${snapshot.cycles.length} cycles, ${snapshot.recoveries.length} recoveries, ` +
      `${snapshot.sleeps.length} sleeps, ${snapshot.workouts.length} workouts.`,
  );

  const golfish = snapshot.workouts.filter((w) =>
    (w.sport_name ?? "").toLowerCase().includes("golf"),
  );
  if (golfish.length > 0) {
    console.log(`${golfish.length} WHOOP workout(s) tagged as golf.`);
  }
}

async function cmdImportCsv(file: string | undefined): Promise<void> {
  if (!file) throw new Error("Usage: wb import-csv <file>");
  const rounds = roundsFromCsv(await readFile(file, "utf8"));
  const all = await saveRounds(rounds);
  console.log(`Imported ${rounds.length} round(s). ${all.length} stored in total.`);
}

async function cmdImportHealth(file: string | undefined): Promise<void> {
  if (!file) throw new Error("Usage: wb import-health <export.xml>");
  console.log("Scanning Apple Health export (this can take a minute on large files)…");
  const rounds = await roundsFromAppleHealthExport(file);
  const all = await saveRounds(rounds);
  console.log(
    `Found ${rounds.length} golf activity/activities. ${all.length} round(s) stored in total.`,
  );
  if (rounds.length > 0) {
    console.log(
      "\nApple Health carries no scorecard — add score/par with `wb import-csv` to make these usable in `wb report`.",
    );
  }
}

async function cmdRounds(): Promise<void> {
  const rounds = await loadRounds();
  if (rounds.length === 0) {
    console.log("No rounds stored. Import some with `wb import-csv` or `wb import-health`.");
    return;
  }
  for (const r of rounds) {
    const stp = scoreToPar(r);
    const scoreText =
      r.score != null ? `${r.score}${stp != null ? ` (${stp >= 0 ? "+" : ""}${stp})` : ""}` : "—";
    console.log(
      `${r.date}  ${String(r.holes).padStart(2)}h  ${scoreText.padEnd(10)} ` +
        `${(r.course ?? "unknown course").padEnd(28)} [${r.source}]`,
    );
  }
}

async function cmdReport(): Promise<void> {
  const [rounds, snapshot] = await Promise.all([loadRounds(), loadSnapshot()]);
  const linked = linkRounds(rounds, snapshot);
  const summary = summarise(linked);

  console.log("WHOOP × 18Birdies — round correlation report\n");
  console.log(`Rounds stored              : ${summary.totalRounds}`);
  console.log(`…with a score and par      : ${summary.roundsWithScore}`);
  console.log(`…with WHOOP data that day  : ${summary.roundsWithPhysiology}`);
  console.log(`…usable for correlation    : ${summary.usableRounds}\n`);

  if (summary.correlations.length === 0) {
    console.log(
      "Not enough overlapping data yet. Each metric needs at least 3 rounds that have\n" +
        "both a score and WHOOP data for that date. Run `wb sync` and import more rounds.",
    );
    return;
  }

  console.log("Correlation with strokes-to-par (negative = more of it, lower score):\n");
  console.log("  metric                 n     r      rho     p       mean");
  for (const c of summary.correlations) {
    console.log(
      `  ${c.label.padEnd(20)} ${String(c.n).padStart(3)}  ` +
        `${fmt(c.pearson).padStart(6)} ${fmt(c.spearman).padStart(6)} ` +
        `${fmt(c.pValue, 3).padStart(6)}  ${fmt(c.metricMean, 1)}${c.unit}`,
    );
  }

  const strongest = summary.correlations[0]!;
  console.log("");
  if (summary.usableRounds < 10) {
    console.log(
      `Only ${summary.usableRounds} usable round(s) — treat these numbers as directional.\n` +
        "Correlations over small samples move a lot with one bad round.",
    );
  } else if (strongest.pValue < 0.05) {
    const dir = strongest.pearson < 0 ? "lower (better)" : "higher (worse)";
    console.log(
      `Strongest signal: higher ${strongest.label} goes with ${dir} scores ` +
        `(r=${fmt(strongest.pearson)}, p=${fmt(strongest.pValue, 3)}).`,
    );
  } else {
    console.log(
      "No metric clears p<0.05 yet. Keep logging rounds — golf scoring is noisy and\n" +
        "physiological effects need a lot of rounds to separate from course and weather.",
    );
  }
}

async function cmdReadiness(date: string | undefined): Promise<void> {
  const target = date ?? today();
  const [rounds, snapshot] = await Promise.all([loadRounds(), loadSnapshot()]);
  const day = indexPhysiology(snapshot).get(target);

  if (!day) {
    console.log(
      `No WHOOP data cached for ${target}. Run \`wb sync\` (WHOOP scores recovery after you wake).`,
    );
    return;
  }

  const correlations = summarise(linkRounds(rounds, snapshot)).correlations;
  const readiness = computeReadiness(day, correlations);

  console.log(`Golf readiness — ${target}\n`);
  console.log(`  ${fmt(readiness.score, 0)}/100  (${readiness.verdict})`);
  console.log(
    `  weights: ${readiness.personalised ? "tuned to your round history" : "defaults (need 8+ scored rounds to tune)"}\n`,
  );
  for (const c of readiness.components) {
    console.log(
      `  ${c.label.padEnd(10)} ${fmt(c.value, 0).padStart(3)}/100  ` +
        `×${fmt(c.weight, 2)}  ${c.detail}`,
    );
  }
  console.log("");
  for (const line of readiness.advice) console.log(`  • ${line}`);
}

/** LAN addresses the iPhone can actually reach — loopback is useless to it. */
function lanAddresses(): string[] {
  const out: string[] = [];
  for (const entries of Object.values(networkInterfaces())) {
    for (const entry of entries ?? []) {
      if (entry.family === "IPv4" && !entry.internal) out.push(entry.address);
    }
  }
  return out;
}

async function cmdServe(args: string[]): Promise<void> {
  const port = Number(flagValue(args, "--port") ?? 8790);
  if (!Number.isFinite(port) || port <= 0 || port > 65535) {
    throw new Error("--port must be a valid port number");
  }

  let token = process.env.WB_INGEST_TOKEN;
  const generated = !token;
  if (!token) token = randomBytes(24).toString("base64url");

  const { port: bound } = startServer({ token, port, hostname: "0.0.0.0" });

  console.log(`Ingest server listening on port ${bound}.\n`);
  if (generated) {
    console.log("Generated a one-off token for this run. Set WB_INGEST_TOKEN to keep it stable:");
    console.log(`  export WB_INGEST_TOKEN=${token}\n`);
  }

  const hosts = lanAddresses();
  if (hosts.length === 0) {
    console.log("No LAN address found — the phone will need a tunnel to reach this machine.");
  } else {
    console.log("Point the iPhone Shortcut at one of these (same Wi-Fi):");
    for (const host of hosts) console.log(`  http://${host}:${bound}/rounds`);
  }

  console.log(`\n  POST /rounds              round JSON from the Shortcut`);
  console.log(`  GET  /readiness?date=…    today's readiness, preformatted for a notification`);
  console.log(`  GET  /health              reachability check (no auth)`);
  console.log(`\nAuthorize with 'Authorization: Bearer <token>' or '?token=<token>'.`);
  console.log("Plain HTTP over your own LAN — do not expose this port to the internet.");
  console.log("\nCtrl-C to stop.");

  // Bun keeps the process alive while the server is bound.
  await new Promise<void>(() => {});
}

/**
 * The round as WHOOP alone recorded it — no watch, no phone on your arm.
 *
 * WHOOP's own activity detection logs the round; this joins it to the recovery,
 * sleep and day strain around it and prints the lot. It is the complete
 * physiological picture of a round, and deliberately says out loud what it
 * cannot include, because "swing path" and "yardage" are the two things people
 * most expect a wrist strap to know and it knows neither.
 */
async function cmdGolf(arg: string | undefined): Promise<void> {
  const snapshot = await loadSnapshot();

  if (arg === "--list" || arg === "-l") {
    const names = sportNames(snapshot);
    if (!names.length) {
      console.log("No workouts cached. Run `wb sync` first.");
      return;
    }
    console.log("Activity names in your WHOOP data:\n");
    for (const { sport, count } of names) {
      const marker = sport.toLowerCase().includes("golf") ? "  <- matched as golf" : "";
      console.log(`  ${String(count).padStart(4)}  ${sport}${marker}`);
    }
    return;
  }

  const rounds = golfWorkouts(snapshot);
  if (!rounds.length) {
    console.log("No golf activity found in your cached WHOOP data.\n");
    console.log("Two things to check:");
    console.log("  1. `wb sync` — the round may not be downloaded yet.");
    console.log("  2. `wb golf --list` — WHOOP may have logged it under another");
    console.log("     name (an unlabelled activity, or 'Walking').  Relabel it in");
    console.log("     the WHOOP app as Golf, then sync again.");
    return;
  }

  const target = arg
    ? rounds.find((w) => w.start.slice(0, 10) === arg || whoopDateOf(w) === arg)
    : rounds[0];

  if (!target) {
    console.log(`No golf activity on ${arg}. Rounds on record:\n`);
    for (const w of rounds.slice(0, 10)) {
      console.log(`  ${whoopDateOf(w)}`);
    }
    return;
  }

  console.log(formatGolfRound(buildGolfRound(snapshot, target)));

  if (!arg && rounds.length > 1) {
    console.log(`\n${rounds.length - 1} earlier round(s): wb golf <YYYY-MM-DD>`);
  }
}

/** A workout's local calendar date, for matching against a user-typed date. */
function whoopDateOf(workout: { start: string; timezone_offset: string }): string {
  return whoopLocalDate(workout.start, workout.timezone_offset);
}

async function main(): Promise<void> {
  const [cmd, ...args] = process.argv.slice(2);

  switch (cmd) {
    case "login":
      return cmdLogin();
    case "status":
      return cmdStatus();
    case "sync":
      return cmdSync(args);
    case "import-csv":
      return cmdImportCsv(args[0]);
    case "import-health":
      return cmdImportHealth(args[0]);
    case "template":
      process.stdout.write(CSV_TEMPLATE);
      return;
    case "rounds":
      return cmdRounds();
    case "report":
      return cmdReport();
    case "readiness":
      return cmdReadiness(args[0]);
    case "golf":
      return cmdGolf(args[0]);
    case "serve":
      return cmdServe(args);
    default:
      process.stdout.write(USAGE);
      if (cmd && cmd !== "help" && cmd !== "--help" && cmd !== "-h") {
        process.exitCode = 1;
      }
  }
}

main().catch((err: unknown) => {
  console.error(`\nError: ${err instanceof Error ? err.message : String(err)}`);
  process.exitCode = 1;
});
