import { describe, expect, test } from "bun:test";
import {
  correlate,
  correlationPValue,
  incompleteBeta,
  mean,
  pearson,
  ranks,
  spearman,
  stdev,
} from "../src/link/stats.ts";

describe("stats", () => {
  test("mean and sample stdev", () => {
    expect(mean([2, 4, 4, 4, 5, 5, 7, 9])).toBe(5);
    // Sample (n-1) stdev of this set is sqrt(32/7).
    expect(stdev([2, 4, 4, 4, 5, 5, 7, 9])).toBeCloseTo(Math.sqrt(32 / 7), 10);
  });

  test("pearson is 1 for a perfect positive line", () => {
    expect(pearson([1, 2, 3, 4], [2, 4, 6, 8])).toBeCloseTo(1, 12);
  });

  test("pearson is -1 for a perfect negative line", () => {
    expect(pearson([1, 2, 3, 4], [8, 6, 4, 2])).toBeCloseTo(-1, 12);
  });

  test("pearson matches a hand-computed value", () => {
    // dx=[-2,-1,0,1,2], dy=[-1,-2,1,0,2] -> cov=8, both SS=10, so r = 8/10.
    expect(pearson([1, 2, 3, 4, 5], [2, 1, 4, 3, 5])).toBeCloseTo(0.8, 10);
  });

  test("pearson is NaN when a side has zero variance", () => {
    expect(Number.isNaN(pearson([1, 1, 1], [1, 2, 3]))).toBe(true);
  });

  test("ranks average ties", () => {
    expect(ranks([10, 20, 20, 40])).toEqual([1, 2.5, 2.5, 4]);
  });

  test("spearman is 1 for any monotonic increasing relation", () => {
    // Non-linear but strictly increasing: Pearson < 1, Spearman == 1.
    const xs = [1, 2, 3, 4, 5];
    const ys = [1, 4, 9, 16, 25];
    expect(spearman(xs, ys)).toBeCloseTo(1, 12);
    expect(pearson(xs, ys)).toBeLessThan(1);
  });

  test("incompleteBeta hits known boundaries", () => {
    expect(incompleteBeta(2, 3, 0)).toBe(0);
    expect(incompleteBeta(2, 3, 1)).toBe(1);
    // I_x(a,a) is symmetric about x=0.5, so it must equal exactly 0.5 there.
    expect(incompleteBeta(3, 3, 0.5)).toBeCloseTo(0.5, 10);
  });

  test("p-value falls as the sample grows for a fixed r", () => {
    const small = correlationPValue(0.6, 6);
    const large = correlationPValue(0.6, 40);
    expect(small).toBeGreaterThan(large);
    expect(large).toBeLessThan(0.05);
  });

  test("p-value for a known t statistic", () => {
    // r=0.5, n=12 -> t = 1.8257, df = 10 -> two-sided p = 0.0979 (scipy).
    expect(correlationPValue(0.5, 12)).toBeCloseTo(0.0979, 3);
  });

  test("p-value is NaN below three pairs", () => {
    expect(Number.isNaN(correlationPValue(0.9, 2))).toBe(true);
  });

  test("correlate bundles n, r, rho and p", () => {
    const result = correlate([1, 2, 3, 4, 5], [5, 4, 3, 2, 1]);
    expect(result.n).toBe(5);
    expect(result.pearson).toBeCloseTo(-1, 12);
    expect(result.spearman).toBeCloseTo(-1, 12);
    expect(result.pValue).toBeCloseTo(0, 10);
  });
});
