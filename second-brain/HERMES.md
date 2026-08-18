# Hermes isn't working — fix it

Hermes Agent is Nous Research's local agent. In this setup it does two jobs:
it's a second agent you can hand work to, and it's the messaging gateway that
lets things reach you when you're away from the terminal.

**Start here.** Hermes ships its own diagnostic, and it is better than guessing:

```bash
hermes doctor --fix
```

That resolves most of what follows on its own. If it can't run at all, work down
this page — the failures are ordered by how often they're the actual cause.

---

## 1. `hermes: command not found`

The most common one, and it is not a broken install. Hermes installs to
`~/.local/bin`, which macOS does not put on `PATH` by default.

```bash
ls -l ~/.local/bin/hermes     # is it there?
```

**If the file exists**, the install worked and only the shell can't see it:

```bash
source ~/.zshrc               # the installer appends the PATH line here
hermes version
```

If that still fails, the PATH line never got written. Add it and reload:

```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

**If the file does not exist**, the install did not complete. Re-run it and
watch for the error rather than scrolling past it:

```bash
curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash
```

Git is the only prerequisite on macOS — the installer brings its own Python
3.11, Node 22, ripgrep and ffmpeg. If it stops on `git: command not found`, run
`xcode-select --install` first.

## 2. It starts, but every request fails — no model configured

Hermes has no API key of its own. Until you give it a provider it will launch,
accept your prompt, and then fail.

```bash
hermes setup --portal    # fastest: OAuth through Nous Portal
# or
hermes model             # pick a provider and paste a key
```

Run these from a plain terminal, **not** from inside a `hermes chat` session —
the model picker is interactive and can't run nested.

## 3. It works in the terminal but Claude Code doesn't see it

These are two separate things: Hermes running, and Hermes *registered with
Claude Code as an MCP server*. Getting the first working does nothing for the
second.

Check what Claude Code has:

```bash
claude mcp list          # is `hermes` in the list?
```

If it isn't:

```bash
claude mcp add hermes -- hermes mcp serve
```

Then **restart Claude Code** — it reads MCP config at startup, so a live session
will not pick up a server added underneath it. Confirm with `/mcp` inside Claude
Code; the entry should be green.

Two things that quietly break this:

- **`hermes` must be on PATH for the process that launches Claude Code.** If you
  start Claude Code from an app launcher rather than a terminal, it may not
  inherit your `~/.zshrc` PATH. Register the absolute path instead:
  `claude mcp add hermes -- /Users/<you>/.local/bin/hermes mcp serve`
- **Test the server by hand before blaming the wiring:** `hermes mcp serve`
  should start and sit there waiting on stdin. If it exits immediately or prints
  a traceback, that traceback is your actual problem.

## 4. It used to work and now doesn't

```bash
hermes update            # pull and reinstall
hermes doctor --fix
```

If an update left it broken, `hermes backup` exists and `hermes update` keeps
one by default — the config is at `~/.hermes/config.yaml` and the data at
`~/.hermes/`.

---

## When you need to ask for help

```bash
hermes dump              # copy-pasteable setup summary, keys redacted
hermes logs --level error --since 1h
```

Paste those two into the conversation. `hermes dump` redacts secrets by default;
don't pass `--show-keys` when sharing it.

## What "working" looks like

```bash
hermes version                       # prints a version
hermes doctor                        # no failures
hermes chat -q "say hello"           # gets a reply
claude mcp list | grep hermes        # registered
brain doctor                         # `hermes` and `mcp: hermes` both ok
```

All five green means Hermes is genuinely wired in, not just installed.

---

## Its place in the brain

Hermes is a *second agent*, not a second memory. When it does something worth
remembering, that still gets written to the vault:

```bash
brain log "handed the log triage to hermes; it found the 429 loop" --kind delegate
```

Otherwise its work disappears when its session does, and the next Claude Code
session has no idea it happened.

Sources: [Hermes Agent installation](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/getting-started/installation.md) ·
[CLI reference](https://github.com/nousresearch/hermes-agent/blob/main/website/docs/reference/cli-commands.md) ·
[MCP](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/features/mcp.md)
