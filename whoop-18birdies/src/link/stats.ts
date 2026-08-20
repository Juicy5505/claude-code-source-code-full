/** Small statistics helpers. No dependencies — these are all short and exact. */

export function mean(xs: number[]): number {
  if (xs.length === 0) return Number.NaN;
  return xs.reduce((a, b) => a + b, 0) / xs.length;
}

/** Sample standard deviation (n-1 denominator). */
export function stdev(xs: number[]): number {
  if (xs.length < 2) return Number.NaN;
  const m = mean(xs);
  const ss = xs.reduce((acc, x) => acc + (x - m) ** 2, 0);
  return Math.sqrt(ss / (xs.length - 1));
}

export function pearson(xs: number[], ys: number[]): number {
  if (xs.length !== ys.length || xs.length < 2) return Number.NaN;
  const mx = mean(xs);
  const my = mean(ys);
  let num = 0;
  let dx = 0;
  let dy = 0;
  for (let i = 0; i < xs.length; i++) {
    const a = xs[i]! - mx;
    const b = ys[i]! - my;
    num += a * b;
    dx += a * a;
    dy += b * b;
  }
  const den = Math.sqrt(dx * dy);
  // Zero variance on either side: the correlation is undefined, not zero.
  return den === 0 ? Number.NaN : num / den;
}

/** Fractional ranks, averaging ties — required for Spearman to stay correct. */
export function ranks(xs: number[]): number[] {
  const idx = xs.map((v, i) => ({ v, i })).sort((a, b) => a.v - b.v);
  const out = new Array<number>(xs.length);
  let i = 0;
  while (i < idx.length) {
    let j = i;
    while (j + 1 < idx.length && idx[j + 1]!.v === idx[i]!.v) j++;
    const avg = (i + j) / 2 + 1;
    for (let k = i; k <= j; k++) out[idx[k]!.i] = avg;
    i = j + 1;
  }
  return out;
}

export function spearman(xs: number[], ys: number[]): number {
  return pearson(ranks(xs), ranks(ys));
}

/**
 * Regularised incomplete beta, via the Lentz continued fraction from
 * Numerical Recipes. Used only to turn a t statistic into a p-value.
 */
function betacf(a: number, b: number, x: number): number {
  const MAXIT = 200;
  const EPS = 3e-14;
  const FPMIN = 1e-300;
  const qab = a + b;
  const qap = a + 1;
  const qam = a - 1;
  let c = 1;
  let d = 1 - (qab * x) / qap;
  if (Math.abs(d) < FPMIN) d = FPMIN;
  d = 1 / d;
  let h = d;
  for (let m = 1; m <= MAXIT; m++) {
    const m2 = 2 * m;
    let aa = (m * (b - m) * x) / ((qam + m2) * (a + m2));
    d = 1 + aa * d;
    if (Math.abs(d) < FPMIN) d = FPMIN;
    c = 1 + aa / c;
    if (Math.abs(c) < FPMIN) c = FPMIN;
    d = 1 / d;
    h *= d * c;
    aa = (-(a + m) * (qab + m) * x) / ((a + m2) * (qap + m2));
    d = 1 + aa * d;
    if (Math.abs(d) < FPMIN) d = FPMIN;
    c = 1 + aa / c;
    if (Math.abs(c) < FPMIN) c = FPMIN;
    d = 1 / d;
    const del = d * c;
    h *= del;
    if (Math.abs(del - 1) < EPS) break;
  }
  return h;
}

function lngamma(z: number): number {
  // Lanczos approximation, g=7, n=9.
  const g = 7;
  const c = [
    0.999_999_999_999_809_93, 676.520_368_121_885_1, -1259.139_216_722_402_8,
    771.323_428_777_653_13, -176.615_029_162_140_6, 12.507_343_278_686_905,
    -0.138_571_095_265_720_12, 9.984_369_578_019_572e-6, 1.505_632_735_149_311_6e-7,
  ];
  if (z < 0.5) {
    return Math.log(Math.PI / Math.sin(Math.PI * z)) - lngamma(1 - z);
  }
  const zz = z - 1;
  let x = c[0]!;
  for (let i = 1; i < g + 2; i++) x += c[i]! / (zz + i);
  const t = zz + g + 0.5;
  return 0.5 * Math.log(2 * Math.PI) + (zz + 0.5) * Math.log(t) - t + Math.log(x);
}

export function incompleteBeta(a: number, b: number, x: number): number {
  if (x <= 0) return 0;
  if (x >= 1) return 1;
  const front = Math.exp(
    lngamma(a + b) - lngamma(a) - lngamma(b) + a * Math.log(x) + b * Math.log(1 - x),
  );
  return x < (a + 1) / (a + b + 2)
    ? (front * betacf(a, b, x)) / a
    : 1 - (front * betacf(b, a, 1 - x)) / b;
}

/**
 * Two-sided p-value for a Pearson correlation of `r` over `n` pairs.
 * Returns NaN when there are too few pairs to say anything.
 */
export function correlationPValue(r: number, n: number): number {
  if (!Number.isFinite(r) || n < 3) return Number.NaN;
  if (Math.abs(r) >= 1) return 0;
  const df = n - 2;
  const t = r * Math.sqrt(df / (1 - r * r));
  return incompleteBeta(df / 2, 0.5, df / (df + t * t));
}

export interface CorrelationResult {
  n: number;
  pearson: number;
  spearman: number;
  pValue: number;
}

export function correlate(xs: number[], ys: number[]): CorrelationResult {
  const r = pearson(xs, ys);
  return {
    n: xs.length,
    pearson: r,
    spearman: spearman(xs, ys),
    pValue: correlationPValue(r, xs.length),
  };
}
