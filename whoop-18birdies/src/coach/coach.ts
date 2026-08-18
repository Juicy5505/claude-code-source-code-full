import Anthropic from "@anthropic-ai/sdk";
import { zodOutputFormat } from "@anthropic-ai/sdk/helpers/zod";
import { z } from "zod";
import type { RoundFacts } from "./facts.ts";

/**
 * The read on a round: what happened, whether your body explains it, and the
 * one thing to work on.
 *
 * Structured rather than prose so `wb coach --json` is consumable and the
 * terminal rendering is ours. `parsed_output` is validated against this schema
 * by the SDK, so a malformed response is an error here rather than a confident
 * paragraph with a missing section.
 */
const CoachRead = z.object({
  headline: z
    .string()
    .describe("One sentence on what actually happened in this round."),
  physiology: z
    .string()
    .nullable()
    .describe(
      "Whether the WHOOP numbers explain the golf, or null when there is no " +
        "WHOOP data or no honest link between them.",
    ),
  findings: z
    .array(
      z.object({
        observation: z.string().describe("What the data shows."),
        evidence: z
          .string()
          .describe("The specific numbers from the fact sheet that support it."),
        confidence: z.enum(["high", "medium", "low"]),
      }),
    )
    .describe("Two to four findings. Fewer is fine when the data is thin."),
  workOn: z.object({
    focus: z.string().describe("The single thing to work on next."),
    drill: z.string().describe("A concrete way to practise it."),
  }),
  dataQuality: z
    .string()
    .nullable()
    .describe(
      "What in this round's numbers should not be trusted, or null when nothing.",
    ),
});

export type CoachRead = z.infer<typeof CoachRead>;

/**
 * The rules exist because the failure mode of a coaching model is not silence,
 * it is fluent invention. Each line below corresponds to something this data
 * genuinely cannot support:
 *
 *  - Swing path, face angle, club head speed, spin, and launch angle come from
 *    a launch monitor. A wrist accelerometer does not see them at any sample
 *    rate, so a model asked to coach a golf swing must be told not to describe
 *    the one thing golf coaching is usually about.
 *  - Distances are stop-to-stop GPS, not carry. A 250 yd reading includes roll.
 *  - Withheld distances stay withheld. When the fact sheet drops them, that is
 *    not an omission to work around.
 */
const SYSTEM = `You are reading one round of golf from wrist-sensor data and, when present, WHOOP physiology. You are a coach, not a cheerleader: say what the numbers show, say what they cannot show, and stop.

WHAT THE DATA IS
- Swings are detected from an Apple Watch on the lead wrist at ~100 Hz.
- "tempo_ratio" is backswing time divided by downswing time. The Tour Tempo benchmark is 3.0:1. Below ~2.4 is a rushed takeaway; above ~3.6 is a slow backswing relative to the downswing.
- "peak_g" is the acceleration magnitude at impact. It tracks effort and contact, not club head speed.
- Distances are GPS stop-to-stop: where you swung, to where you swung next. That is total distance including roll, not carry.
- "cv" is the coefficient of variation — spread relative to the mean. Lower is more repeatable.

WHAT THE DATA IS NOT
You cannot see swing path, club face angle, club head speed, attack angle, spin, launch angle, ball flight, shot shape, lie, club selection, or score. Never describe any of them, never infer them, and never suggest the user check them here. If a finding would require one of them, do not make the finding.

RULES
1. Every number you cite must appear in the fact sheet. Do not compute new statistics, do not estimate, and do not round differently.
2. Honour "n". A statistic over 4 swings is an observation; over 40 it is a pattern. Set confidence accordingly, and prefer "low" when in doubt.
3. If "distancesWithheld" is true, do not discuss yardages at all beyond noting they were withheld and why. The withheld numbers measure a cart, not a golfer.
4. Read every entry in "caveats" and let it constrain you. They are there because something specific went wrong.
5. If "whoop" is null, set "physiology" to null. Do not speculate about sleep or recovery you were not given.
6. Only claim a link between physiology and performance when a split or spread in the fact sheet actually supports it. "Recovery was 42%" alone explains nothing.
7. Be concrete and brief. No praise, no filler, no restating the fact sheet back.`;

export interface CoachOptions {
  /** Override for testing; defaults to a client that resolves ambient credentials. */
  client?: Anthropic;
  model?: string;
}

export const COACH_MODEL = "claude-opus-5";

/**
 * Ask Claude to read the round.
 *
 * Non-streaming on purpose. The output is a few hundred tokens of structured
 * JSON, well inside the SDK's default timeout, and `messages.parse()` — which
 * validates the response against the schema — has no streaming form. Streaming
 * would buy nothing but a partially-typed object.
 *
 * Not prompt-cached, also on purpose: the system prompt is well under the
 * ~1024-token minimum cacheable prefix, so a `cache_control` breakpoint here
 * would read as an optimisation while silently never caching anything.
 */
export async function coachRound(
  facts: RoundFacts,
  options: CoachOptions = {},
): Promise<CoachRead> {
  const client = options.client ?? new Anthropic();

  const response = await client.messages.parse({
    model: options.model ?? COACH_MODEL,
    max_tokens: 16000,
    system: SYSTEM,
    // Thinking is on by default on Claude Opus 5, so it is not configured here.
    // Effort is: reading a round is a judgement task, and the cost of a shallow
    // read is a confident wrong diagnosis rather than a slow one.
    output_config: {
      effort: "high",
      format: zodOutputFormat(CoachRead),
    },
    messages: [
      {
        role: "user",
        content:
          "Read this round.\n\n```json\n" +
          JSON.stringify(facts, null, 2) +
          "\n```",
      },
    ],
  });

  if (response.stop_reason === "refusal") {
    throw new Error(
      "The model declined to answer" +
        (response.stop_details?.explanation
          ? `: ${response.stop_details.explanation}`
          : "."),
    );
  }

  const read = response.parsed_output;
  if (!read) {
    throw new Error(
      "The model's reply did not match the expected shape. Re-run, and if it " +
        "keeps happening the schema and the prompt have drifted apart.",
    );
  }
  return read;
}

const CREDENTIALS_HELP =
  "`wb coach` needs an Anthropic credential. Either:\n" +
  "  export ANTHROPIC_API_KEY=...   (console.anthropic.com)\n" +
  "  or run `ant auth login`, which the SDK picks up with no env var set.\n" +
  "Nothing else in `wb` needs this — WHOOP and the watch work without it.";

/**
 * Turns an API failure into something that says what to do about it.
 *
 * Checked most specific first. A single broad catch would report an expired
 * key, a rate limit, and an unreachable network as the same event, which is
 * the difference between "wait a minute" and "log in again".
 */
export function explainError(error: unknown): string {
  if (error instanceof Anthropic.AuthenticationError) {
    return `Anthropic rejected the credentials.\n${CREDENTIALS_HELP}`;
  }
  if (error instanceof Anthropic.RateLimitError) {
    return "Rate limited by the Anthropic API. Wait a moment and re-run.";
  }
  if (error instanceof Anthropic.BadRequestError) {
    return `The request was rejected: ${error.message}`;
  }
  if (error instanceof Anthropic.APIConnectionError) {
    return "Could not reach the Anthropic API. Check the network and re-run.";
  }
  if (error instanceof Anthropic.APIError) {
    return `Anthropic API error ${error.status ?? "?"}: ${error.message}`;
  }

  // Anything that is not an APIError never reached the wire. In practice the
  // dominant member of that set is "no credentials configured", which the SDK
  // raises as a bare Error with no class to match on — so the structural test
  // is that the request failed locally AND nothing is exported to resolve.
  // The original message is still shown; this only adds the fix.
  const message = error instanceof Error ? error.message : String(error);
  if (!process.env.ANTHROPIC_API_KEY && !process.env.ANTHROPIC_AUTH_TOKEN) {
    return `${CREDENTIALS_HELP}\n\n  (${message})`;
  }
  return message;
}

/** Render for a terminal. Mirrors the layout of `wb golf` and `wb report`. */
export function formatCoachRead(read: CoachRead, facts: RoundFacts): string {
  const lines: string[] = [];
  const head = facts.date ? `Round of ${facts.date}` : "Round";
  lines.push(head);
  lines.push("=".repeat(head.length));
  lines.push("");
  lines.push(read.headline);
  lines.push("");

  const scope: string[] = [`${facts.swingCount} swings`];
  if (facts.durationMin !== null) scope.push(`${facts.durationMin} min`);
  if (facts.tempo) scope.push(`tempo ${facts.tempo.mean.toFixed(2)}:1`);
  if (facts.fullShots) {
    scope.push(`${facts.fullShots.n} shots measured`);
    if (facts.longestYd !== null) scope.push(`longest ${facts.longestYd} yd`);
  }
  lines.push(scope.join(" · "));
  lines.push("");

  if (read.physiology) {
    lines.push("Body");
    lines.push(`  ${read.physiology}`);
    lines.push("");
  }

  if (read.findings.length > 0) {
    lines.push("What the round shows");
    for (const finding of read.findings) {
      lines.push(`  • ${finding.observation}  [${finding.confidence}]`);
      lines.push(`    ${finding.evidence}`);
    }
    lines.push("");
  }

  lines.push("Work on");
  lines.push(`  ${read.workOn.focus}`);
  lines.push(`  Drill: ${read.workOn.drill}`);

  if (read.dataQuality) {
    lines.push("");
    lines.push("Trust");
    lines.push(`  ${read.dataQuality}`);
  }

  return lines.join("\n");
}
