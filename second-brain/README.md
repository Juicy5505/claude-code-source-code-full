# Second brain — Obsidian as Claude Code's memory

> "Everything should be written down in Obsidian. That is your memory. That is
> your mind. That is your brain."

This makes that literally true, for every project, without you having to ask.

A Claude Code session starts with no memory of the last one. An Obsidian vault
has no such problem. So: **every session reads the vault on the way in and
writes to it as it works** — prompts, file changes, decisions, verified facts,
and what was left unfinished.

The important design choice is that this is a **program, not a paragraph**.
Standing instructions to "remember to take notes" get crowded out of a long
context and quietly stop happening around hour two. Hooks don't — the harness
fires them whether or not the model remembers.

---

## Install (on your Mac)

```bash
git clone https://github.com/juicy5505/claude-code-source-code-full.git
cd claude-code-source-code-full
./second-brain/install.sh
source ~/.zshrc
```

Then, in any project you work on:

```bash
cd ~/code/some-project
brain init          # creates ~/Obsidian/some-project and binds it here
```

Open that folder in Obsidian (**Open folder as vault**) and start Claude Code in
the project. That's it — capture is automatic from here.

> This must run **on your Mac**. A cloud session has no access to your
> filesystem, your Obsidian, or your Claude Code config, so it cannot install
> any of this for you.

## What gets installed

| Where | What |
|---|---|
| `~/.local/bin/brain` | the CLI (symlink to this repo) |
| `~/.claude/settings.json` | four hooks — backed up first, merged, never overwritten |
| `~/.claude/CLAUDE.md` | the memory contract, inside `<!-- BEGIN second-brain -->` markers |
| `~/Obsidian/<project>/` | one vault per project |

The four hooks are the whole mechanism:

| Hook | Fires | Does |
|---|---|---|
| `SessionStart` | new/resumed session | prints the vault's recall **into the session's context** |
| `UserPromptSubmit` | every prompt | appends it verbatim to today's note |
| `PostToolUse` | `Edit`/`Write`/`NotebookEdit` | records which file changed, once per file per day |
| `SessionEnd` | session closes | carries the unfinished part into Open Threads |

`SessionEnd`, not `Stop` — `Stop` fires after every single reply and would turn
the vault into a heartbeat log.

## The vault

```
~/Obsidian/<project>/
├── MOC.md              map of content — every note reachable in a hop or two
├── CLAUDE.md           the contract, read at session start
├── 00-Inbox/           unfiled, to triage
├── 01-Sessions/        one note per day — prompts, actions, decisions
├── 02-Decisions/       one note per decision, with the reasoning
├── 03-Knowledge/       verified facts and constraints
├── 04-Code/            code artifacts with provenance
├── 05-Graph/           Graphify output — derived, never hand-edited
├── 06-Integrations/    Hermes, n8n, Figma, Canva, OpenClaw wiring
└── 99-Meta/            Toolchain, Open Threads
```

Capture is raw and append-only in `01-Sessions/`; distillation is deliberate and
lives in `02-Decisions/` and `03-Knowledge/`. That split is the point — you get
a complete record *and* something readable.

## Commands

```bash
brain init                 # create/attach a vault for this project
brain recall "auth"        # what a new session should know
brain search "429"         # grep the vault, newest first

brain log "shipped the retry fix" --kind fix
brain decision "Use Postgres" --why "..." --rejected "..." --revisit "..."
brain note "WHOOP exposes no motion data" --body "verified by BLE teardown"

brain graph --code-only              # build the code graph into the vault
brain graph --query "what calls X?"  # ask it

brain index                # rebuild the MOC, list orphan notes
brain doctor               # check the whole toolchain
brain list                 # every vault on this machine
```

## Tests

```bash
python3 second-brain/test_brain.py
```

33 tests, no dependencies, run against real temporary vaults on disk — because
the failure modes that matter here are filesystem ones: clobbering a note,
duplicating a section, losing the binding between a project and its vault.

## The rest of the toolchain

`brain doctor` reports on all of it. See [INTEGRATIONS.md](INTEGRATIONS.md) for
how the pieces fit, and [HERMES.md](HERMES.md) if Hermes specifically is not
working.

| Tool | Answers |
|---|---|
| **Obsidian** | what did we decide, learn, and try? |
| **Graphify** | what does this code actually do? |
| **n8n** | run this on a schedule or an event |
| **Figma** | what is this screen supposed to look like? |
| **Canva** | make the deck, the post, the brand asset |
| **Hermes** | a second agent; reach me over messages |
| **OpenClaw** | do something on my machine while I'm away |

## Honest limits

- **Nothing here is magic about "everything".** The hooks capture prompts, file
  changes, and session boundaries. They do not capture reasoning — that only
  reaches the vault when Claude calls `brain decision` / `brain note`, which is
  a judgement call the contract in `CLAUDE-global.md` asks for but cannot force.
  A session that decides something important and doesn't write it down has still
  forgotten it.
- **Recall is bounded.** `session-start` injects open threads, the last three
  sessions, and the titles of recent decisions and knowledge notes — not the
  whole vault. Deep history is reached on demand with `brain search`.
- **One vault per project means cross-project memory is manual.** That is the
  deliberate trade: a single shared vault would make every session's recall
  noisier the more projects you have.
- **The vault is plain Markdown on disk.** No plugin, no database, no lock-in —
  if you delete `brain` tomorrow, every note stays readable.
