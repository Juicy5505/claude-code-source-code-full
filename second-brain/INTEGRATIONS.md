# The toolchain

Seven tools, one brain. This is what each one is actually for, how it connects
to Claude Code, and where the seams are — so you reach for the right one instead
of the one you used last.

Run `brain doctor` for the live status of every row on this page.

| Tool | Answers | Connects via | Needs |
|---|---|---|---|
| **Obsidian** | what did we decide, learn, try? | the filesystem | nothing — plain Markdown |
| **Graphify** | what does this code actually do? | `/graphify` skill + `brain graph` | `uv tool install graphifyy` |
| **n8n** | run this on a schedule or an event | MCP | your instance URL + API key |
| **Figma** | what should this screen look like? | MCP | desktop app, or the remote server |
| **Canva** | make the deck / post / brand asset | MCP | OAuth on first use |
| **Hermes** | a second agent; reach me over messages | MCP (`hermes mcp serve`) | a model provider |
| **OpenClaw** | act on my machine while I'm away | its own gateway | Node 22+ |

---

## The two kinds of memory

The single most useful distinction here, and the one people get wrong:

**Obsidian is episodic memory.** What happened, what was chosen, what turned out
to be false. Written by hand (well — by Claude), never derived, permanent.

**Graphify is structural memory.** What the code *is*: a real call graph from
AST parsing, with `file:line` citations on every edge. Derived, regenerated,
never hand-edited.

They meet in exactly one place — the vault's `05-Graph/` folder, where
`brain graph` writes Graphify's output. That lets a decision note link straight
to the call path that justified it. Do not put prose in the graph folder, and do
not paste graph output into `03-Knowledge/`; link across instead.

---

## Graphify

```bash
brain graph --code-only              # build, fully local, no API key
brain graph --update                 # re-extract only what changed
brain graph --query "what calls the auth middleware?"
graphify path "LoginForm" "SessionStore"
graphify explain "WorkoutManager"
```

`brain graph` sets `GRAPHIFY_OUT` to the vault's `05-Graph/`, so the graph lands
in the brain instead of a stray `graphify-out/` beside your source.

**Use it before reading files.** On an unfamiliar codebase a query returns the
call path with citations, which beats grepping until the shape becomes clear.
Two caveats worth holding onto:

- Every edge is tagged `EXTRACTED`, `INFERRED`, or `AMBIGUOUS`. Inferred and
  ambiguous edges are leads to confirm in the source, not facts.
- `--code-only` is AST-only: nothing leaves the machine, no LLM credit is spent.
  The full pipeline (docs, SQL, PDFs) needs a key and does make calls.

Rebuild after structural change, or the graph confidently describes code that no
longer exists.

## Figma and Canva — not the same job

Both are "design", and confusing them wastes time.

**Figma is the specification you build a product screen against.** When you're
writing CSS or laying out a component, read the design rather than inventing
spacing and colour. Two servers exist:

```bash
# Desktop — needs Figma open, Dev Mode on, MCP server toggled in preferences.
# Gives you selection-based context: "the frame I have selected".
claude mcp add --transport http figma-desktop http://127.0.0.1:3845/mcp
```

The local endpoint only exists while the app is running with the server enabled.
If `brain doctor` says `figma mcp: local server down`, that's what it means —
open Figma, or use the remote server, which needs nothing running locally.

**Canva is for artefacts a person looks at rather than runs** — decks, social
posts, brand assets:

```bash
claude mcp add --transport http canva https://mcp.canva.com/mcp
```

Hosted, so nothing runs locally; you authenticate on first use. Pull the brand
kit rather than picking colours yourself — that's the whole reason to use it
over generating an image.

## n8n

Scheduled and event-driven automation: the things that should happen without a
session being open. Register it against your own instance:

```bash
claude mcp add --transport http n8n https://<your-n8n-host>/mcp
```

The natural pairing with this brain is **outbound**: an n8n workflow that reads
the vault's Open Threads on a schedule and messages you, or one that fires on a
webhook and appends to the inbox. The vault is plain Markdown on disk, so n8n
needs no special support to read or write it.

## Hermes

A second agent, and the messaging gateway that reaches you off the terminal.

```bash
claude mcp add hermes -- hermes mcp serve
```

If it isn't working, [HERMES.md](HERMES.md) covers the four failure modes in the
order they actually occur — `hermes: command not found` (a PATH problem, not a
broken install) being far and away the most common.

Hermes is a second *agent*, not a second *memory*. When you hand it work, log
that in the vault — otherwise the result dies with its session and the next
Claude Code session has no idea it happened.

## OpenClaw

An always-on personal assistant that runs on the Mac.

```bash
curl -fsSL https://openclaw.ai/install.sh | bash
```

macOS is the strongest platform for it: the `imsg` skill lets it send and
receive iMessages through your Mac's Messages app, which no other platform
offers. That makes it the natural "reach me" endpoint for anything long-running.

Treat it with the care that implies — it holds real credentials and can act
without you watching. Give it the narrowest set of skills that does the job.

---

## Wiring it all at once

```bash
./second-brain/install.sh     # brain + hooks + Graphify + MCP registration
brain doctor                  # what's green, what isn't
```

`install.sh` cannot register n8n for you — it needs your instance URL and key —
and it will say so rather than guessing.

**Restart Claude Code after adding any MCP server.** It reads MCP configuration
at startup, so a live session will not see a server added underneath it. This is
the single most common reason a correctly-registered server appears dead.

---

## What connects to what, honestly

Not every pair of these tools has a real channel between them, and pretending
otherwise wastes a lot of time. What genuinely exists:

- **Claude Code → all six**, via MCP or the CLI. This is the hub; everything
  routes through it.
- **Graphify → Obsidian**, via `brain graph` writing into `05-Graph/`.
- **Everything → Obsidian**, via `brain log` / `brain note` — but only because
  Claude Code calls them. Nothing writes to the vault on its own.
- **n8n → Obsidian**, if you point a workflow at the vault directory. Plain
  files, so this is straightforward.

What does *not* exist: direct tool-to-tool links that skip Claude Code. Figma
does not talk to Canva, Hermes does not read your Graphify graph, OpenClaw has
no view of the vault unless you give it one. The integration is a hub and
spokes, not a mesh — and the hub is the session you're typing into.
