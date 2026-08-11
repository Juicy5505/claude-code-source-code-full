import { describe, expect, test } from "bun:test";
import { normaliseDate, parseCsv, roundsFromCsv } from "../src/rounds/csv.ts";
import {
  localDateOf,
  parseAppleDate,
  scanWorkoutTags,
  workoutFromTag,
  workoutMatches,
} from "../src/rounds/appleHealth.ts";
import { dedupeRounds, roundId, scoreToPar } from "../src/rounds/types.ts";

describe("csv parsing", () => {
  test("handles quoted fields with commas and doubled quotes", () => {
    const rows = parseCsv('a,b\n"Pebble, ""Old"" Course",2\n');
    expect(rows[1]).toEqual(['Pebble, "Old" Course', "2"]);
  });

  test("handles CRLF line endings and a BOM", () => {
    const rows = parseCsv("﻿a,b\r\n1,2\r\n");
    expect(rows[0]).toEqual(["a", "b"]);
    expect(rows[1]).toEqual(["1", "2"]);
  });

  test("normalises ISO and US dates", () => {
    expect(normaliseDate("2026-05-04")).toBe("2026-05-04");
    expect(normaliseDate("5/4/2026")).toBe("2026-05-04");
    expect(normaliseDate("not a date")).toBeNull();
  });

  test("imports rounds with aliased headers", () => {
    const rounds = roundsFromCsv(
      "Round Date,Club,Holes,Course Par,Gross,Total Putts\n2026-05-04,Torrey Pines,18,72,86,34\n",
    );
    expect(rounds).toHaveLength(1);
    const r = rounds[0]!;
    expect(r.date).toBe("2026-05-04");
    expect(r.course).toBe("Torrey Pines");
    expect(r.score).toBe(86);
    expect(r.par).toBe(72);
    expect(r.putts).toBe(34);
    expect(r.source).toBe("csv");
  });

  test("defaults to 18 holes and skips unparseable dates", () => {
    const rounds = roundsFromCsv("date,score,par\n2026-05-04,86,72\ngarbage,90,72\n");
    expect(rounds).toHaveLength(1);
    expect(rounds[0]!.holes).toBe(18);
  });

  test("rejects a CSV with no date column", () => {
    expect(() => roundsFromCsv("course,score\nTorrey,86\n")).toThrow(/date/);
  });
});

describe("round model", () => {
  test("scoreToPar doubles a 9-hole differential", () => {
    const base = { id: "x", date: "2026-05-04", source: "csv" as const };
    expect(scoreToPar({ ...base, holes: 18, score: 86, par: 72 })).toBe(14);
    expect(scoreToPar({ ...base, holes: 9, score: 43, par: 36 })).toBe(14);
  });

  test("scoreToPar is null without both score and par", () => {
    expect(
      scoreToPar({ id: "x", date: "2026-05-04", holes: 18, score: 86, source: "csv" }),
    ).toBeNull();
  });

  test("roundId is stable and slug-safe", () => {
    expect(roundId("2026-05-04", "Torrey Pines South!", 18)).toBe(
      "2026-05-04_torrey-pines-south_18",
    );
  });

  test("dedupe keeps the richer record for a repeated id", () => {
    const id = roundId("2026-05-04", "Torrey", 18);
    const sparse = { id, date: "2026-05-04", holes: 18, source: "apple-health" as const };
    const rich = { ...sparse, score: 86, par: 72, putts: 34, source: "csv" as const };
    const merged = dedupeRounds([sparse, rich]);
    expect(merged).toHaveLength(1);
    expect(merged[0]!.score).toBe(86);
  });
});

describe("apple health", () => {
  const tag =
    '<Workout workoutActivityType="HKWorkoutActivityTypeGolf" duration="245" durationUnit="min" ' +
    'totalDistance="7.2" totalDistanceUnit="km" sourceName="18Birdies" ' +
    'startDate="2026-05-04 08:10:00 -0700" endDate="2026-05-04 12:15:00 -0700">';

  test("parses Apple's space-separated offset timestamps", () => {
    const d = parseAppleDate("2026-05-04 08:10:00 -0700");
    expect(d?.toISOString()).toBe("2026-05-04T15:10:00.000Z");
  });

  test("local date uses the recorded offset, not UTC", () => {
    // 21:30 Pacific is already the next day in UTC; the round is still the 4th.
    expect(localDateOf("2026-05-04 21:30:00 -0700")).toBe("2026-05-04");
  });

  test("extracts workout attributes", () => {
    const w = workoutFromTag(tag)!;
    expect(w.activityType).toBe("HKWorkoutActivityTypeGolf");
    expect(w.sourceName).toBe("18Birdies");
    expect(w.durationMinutes).toBe(245);
    expect(w.distanceKm).toBeCloseTo(7.2, 6);
  });

  test("converts miles to km", () => {
    const w = workoutFromTag(
      tag.replace('totalDistanceUnit="km"', 'totalDistanceUnit="mi"'),
    )!;
    expect(w.distanceKm).toBeCloseTo(7.2 * 1.609_344, 6);
  });

  test("matches golf by activity type or by 18Birdies as the source", () => {
    const golf = workoutFromTag(tag)!;
    expect(workoutMatches(golf)).toBe(true);

    // 18Birdies does not tag its activity as golf; source matching is what saves it.
    const untyped = workoutFromTag(
      tag.replace("HKWorkoutActivityTypeGolf", "HKWorkoutActivityTypeWalking"),
    )!;
    expect(workoutMatches(untyped)).toBe(true);

    const unrelated = workoutFromTag(
      tag
        .replace("HKWorkoutActivityTypeGolf", "HKWorkoutActivityTypeRunning")
        .replace('sourceName="18Birdies"', 'sourceName="Nike Run Club"'),
    )!;
    expect(workoutMatches(unrelated)).toBe(false);
  });

  test("scans multiple workout tags out of a chunk", () => {
    expect(scanWorkoutTags(`${tag}<Record/>${tag}`)).toHaveLength(2);
  });

  test("rejects a tag missing required attributes", () => {
    expect(workoutFromTag('<Workout duration="245">')).toBeNull();
  });
});
