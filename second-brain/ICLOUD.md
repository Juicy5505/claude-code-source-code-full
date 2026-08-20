# Keeping things in iCloud

Three different things in this setup can live in iCloud, and the right answer is
different for each. Two are fine. One is not.

| | In iCloud? | Why |
|---|---|---|
| **Obsidian vault** | Yes — do it | Officially supported, and syncing to your phone is the point. One setting to change. |
| **`~/.whoop-18birdies`** (data) | Fine | Small JSON files. Set `WB_DATA_DIR` so the tools find it. |
| **The git repo** | **No** | See below. This one can actually corrupt. |

---

## The vault — yes, with one setting

Obsidian documents iCloud sync, and a vault in
`~/Library/Mobile Documents/iCloud~md~obsidian/Documents/` is the normal way to
have the same notes on a Mac and an iPhone.

**Turn off eviction for the vault.** In Finder, right-click the vault folder →
**Keep Downloaded**.

This is the one thing that matters, and it is worth understanding rather than
just doing. With *Optimize Mac Storage* on, macOS reclaims space by replacing a
file's contents with a placeholder named `.YourNote.md.icloud` — and the real
filename disappears from the directory. Nothing errors. A glob for `*.md` simply
does not find it.

For a vault whose entire job is being read at the start of every session, that
is silent amnesia. `brain doctor` checks for it:

```
[MISS] vault storage  iCloud: 2 note(s) evicted and INVISIBLE to recall —
                      2026-08-17 Use Postgres.md, WHOOP BLE facts.md.
                      Fix: right-click the vault in Finder → Keep Downloaded,
                      or run `brctl download <vault>`
```

What eviction costs is specific: a dangling `[[link]]` survives in the session
log, so the *title* still shows up. What is gone is the note — the reasoning,
the rejected alternatives, the revisit condition — and the curated
"settled, do not re-litigate" list no longer offers it. A future session sees a
title it cannot read, with nothing to say the note is unreachable. That is worse
than the note being plainly absent.

### If you moved a vault that was already bound

The binding stores an absolute path, so it goes stale. Every command says so
rather than quietly starting a fresh vault:

```
brain: vault /Volumes/Alex Drive/Obsidian/myproject is registered but missing.
  It was moved or deleted. Re-run `brain init --vault <new path>`.
```

Rebind it, and the history comes with it:

```bash
cd ~/code/myproject
brain init --vault ~/Library/Mobile\ Documents/iCloud~md~obsidian/Documents/myproject
brain recall     # confirm the old decisions are still there
```

Commit the updated `.brain.json` — that is what lets a clone on another machine
find the same vault.

### Two Macs writing at once

iCloud has no merge. If two machines edit the same note before syncing, you get
`YourNote.md` and `YourNote 2.md`, and nothing tells you. The `brain` hooks take
a lock, but that lock is per-machine — it cannot see the other Mac.

In practice this is rarely a problem, because a session note is only written by
the machine you are working on. If you do run Claude Code on two Macs against
one vault, expect the occasional ` 2.md` and merge it by hand.

---

## The data directory — fine, just point at it

`~/.whoop-18birdies` holds the WHOOP cache, rounds, tokens and uploaded
sessions. It is a handful of small JSON files and syncs without trouble.

If you moved it, tell the tools where it went:

```bash
export WB_DATA_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/whoop-18birdies"
```

Put that line in `~/.zshrc` so every shell picks it up.

**One caveat.** `tokens.json` holds your WHOOP OAuth refresh token, written
`0600`. Syncing it to iCloud means it exists on Apple's servers and on every
device signed into your account. That is a reasonable trade if you want
`wb sync` to work from a laptop and a desktop; if you would rather it did not,
leave the data directory local and sync only what you care about.

---

## The git repo — keep it on local disk

**Do not put the working clone in iCloud Drive.** Two mechanisms make it a bad
idea, and neither announces itself:

1. **Eviction hits `.git` too.** Git's object and pack files are exactly what
   *Optimize Mac Storage* considers cold — you do not open them in an app, and
   they are large. An evicted object is a missing object, and a repository with
   missing objects reports corruption.
2. **The sync daemon writes concurrently.** Git assumes it is the only thing
   touching `.git`. A sync that copies a half-written index or lockfile between
   machines produces conflicts inside git's own metadata, where they are far
   harder to reason about than a conflicted note.

Keep the clone somewhere local:

```bash
mv ~/Library/Mobile\ Documents/com~apple~CloudDocs/claude-code-source-code-full \
   ~/code/claude-code-source-code-full
cd ~/code/claude-code-source-code-full
git status          # confirm it is intact
git fsck            # confirm no objects were lost on the way
```

You do not lose anything by this. **The repo is already synced — by git.** That
is what `git push` is for, and it is a sync designed for exactly this data, with
real merges and a full history. iCloud on top of it adds risk and no capability.

If `git fsck` reports missing or broken objects after a stint in iCloud, do not
try to repair it in place — re-clone and reapply anything uncommitted:

```bash
cd ~/code
git -C claude-code-source-code-full diff > /tmp/uncommitted.patch   # save your work first
git clone https://github.com/juicy5505/claude-code-source-code-full.git fresh
cd fresh && git apply /tmp/uncommitted.patch
```

---

## Checking it all at once

```bash
brain doctor        # vault binding, cloud storage, evicted notes, toolchain
wb status           # is the data directory found, are you linked to WHOOP
git fsck            # is the repository intact
```
