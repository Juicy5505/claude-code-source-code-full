## Obsidian is your memory

You do not remember anything between sessions. An Obsidian vault does. So the
vault is not a place you file reports — it is where your memory physically
lives, and a session that does not write to it has genuinely forgotten
everything it just learned.

Hooks already capture the raw layer for you: every prompt, every file you
change, and the session's open threads land in the vault whether or not you
think about it. What the hooks cannot do is the part that requires judgement —
noticing that something was *decided*, or that something was *established as
true*. That part is yours.

### Every project gets its own vault

```bash
brain where     # is this project already bound?
brain init      # if not: creates ~/Obsidian/<project> and binds it here
```

Run `brain init` the first time you work in any project. Commit the `.brain.json`
marker it writes, so a clone on another machine finds the same brain.

### On the way in

The `SessionStart` hook has already put the vault's recall at the top of your
context: open threads, the last few sessions, the decisions and knowledge notes.
**Read it before you start.** Specifically:

- A note in `02-Decisions/` is **settled**. Do not re-litigate it, and do not
  quietly reverse it. If new evidence overturns one, say so out loud and write a
  new decision note that supersedes it by name.
- A note in `03-Knowledge/` was **verified once, at cost**. Trust it instead of
  re-deriving it. If you find it is wrong, correct the note — that is the single
  most valuable thing you can do in a session.

Need more than the hook gave you: `brain recall "<topic>"` or `brain search "<term>"`.

### On the way through

| The moment | Write it |
|---|---|
| a step completes | `brain log "what happened" --kind build\|test\|fix` |
| you choose between real options | `brain decision "title" --what … --why … --rejected … --revisit …` |
| you verify a fact, limit, or API | `brain note "title" --body "what is true, and how you checked"` |
| you hit a dead end | `brain note "title" --folder 00-Inbox --body "what failed and the exact error"` |

Write the reasoning, not just the outcome. "Chose Postgres" is worth nothing in
three months. "Chose Postgres because the queue needs transactional enqueue,
which Redis cannot give us — measured, see the note" is why the brain exists.

**Record failures.** A failed approach is worth more than a successful one,
because the next session will otherwise spend an hour rediscovering it. Write
down what you tried, what broke, and the error verbatim.

### Two things not to do

- **Never fabricate a `[[link]]`.** A wikilink to a note that does not exist is
  a dead end that looks like knowledge. Create the note or drop the link.
- **Never treat the vault as a substitute for telling the user.** It is your
  memory, not your reply. Say the important thing in the conversation *and*
  write it down.

### The rest of the toolchain

Each of these answers a different question. Reach for the one that fits.

| Question | Tool |
|---|---|
| *what did we decide, learn, try?* | **Obsidian** — this vault, via `brain` |
| *what does this code actually do?* | **Graphify** — `/graphify` skill, a real call graph, no guessing |
| *do this on a schedule or on an event* | **n8n** — MCP |
| *what is this screen supposed to look like?* | **Figma** — MCP; the design is the source of truth, do not invent spacing or colour |
| *make the deck, the social post, the brand asset* | **Canva** — MCP; pull the brand kit rather than picking colours yourself |
| *ask a second agent / reach me over messages* | **Hermes** — MCP |
| *do something on my machine while I am away* | **OpenClaw** |

Figma and Canva are both "design", and it is worth not confusing them: **Figma
is the spec you build a product screen against**, Canva is where brand and
presentation artefacts are made. If you are writing CSS, read Figma. If you are
producing something a person will look at rather than run, use Canva.

When one of them produces something durable — a graph export, a workflow you
built, a design token set — write a note about it in the vault. The tools are
where the work happens; the vault is what remembers that it happened.

### Use Graphify before you go reading files

On any codebase you do not already know, build the graph once and ask it, rather
than opening files until the shape becomes clear:

```bash
brain graph --code-only                       # local AST parse, no API key, once
brain graph --query "what calls the auth middleware?"
graphify path "LoginForm" "SessionStore"      # the exact route between two things
graphify explain "WorkoutManager"             # everything known about one node
```

Its output is written into the vault's `05-Graph/`, so the graph and the
reasoning live in the same brain. Two habits make this pay off:

- **Ask the graph first, read files second.** A query returns the call path with
  `file:line` citations, which is both faster and more complete than grepping.
  Every edge is tagged `EXTRACTED`, `INFERRED`, or `AMBIGUOUS` — treat inferred
  and ambiguous edges as leads to confirm in the source, not as facts.
- **Rebuild after structural change**, with `brain graph --update`, or the graph
  quietly describes code that no longer exists.

Never hand-edit `05-Graph/`. It is derived; your prose belongs in `03-Knowledge/`
with a link across to the node that supports it.
