#!/usr/bin/env bash
#
# Wire the Obsidian brain into Claude Code on this machine.
#
# Run this ON YOUR MAC, in the repo checkout — not in a cloud session, which has
# no access to your filesystem, your Obsidian, or your Claude Code config.
#
#   ./second-brain/install.sh              # everything
#   ./second-brain/install.sh --hooks-only # just the capture hooks
#   ./second-brain/install.sh --no-mcp     # skip Hermes/n8n/Figma registration
#
# Every step is idempotent and backs up what it touches. Nothing is deleted.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="${HOME}/.local/bin"
CLAUDE_DIR="${HOME}/.claude"
SETTINGS="${CLAUDE_DIR}/settings.json"
GLOBAL_MD="${CLAUDE_DIR}/CLAUDE.md"
STAMP="$(date +%Y%m%d-%H%M%S)"

HOOKS_ONLY=0
DO_MCP=1
for arg in "$@"; do
  case "$arg" in
    --hooks-only) HOOKS_ONLY=1 ;;
    --no-mcp)     DO_MCP=0 ;;
    -h|--help)    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

say()  { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
ok()   { printf '    \033[32mok\033[0m   %s\n' "$1"; }
warn() { printf '    \033[33mnote\033[0m %s\n' "$1"; }

command -v python3 >/dev/null || { echo "python3 is required" >&2; exit 1; }

# --------------------------------------------------------------- 1. the CLI

say "Installing the brain CLI"
mkdir -p "$BIN_DIR"
ln -sf "${HERE}/brain" "${BIN_DIR}/brain"
ok "${BIN_DIR}/brain -> ${HERE}/brain"

if ! command -v brain >/dev/null 2>&1; then
  warn "${BIN_DIR} is not on your PATH. Adding it to ~/.zshrc."
  if ! grep -qs '.local/bin' "${HOME}/.zshrc" 2>/dev/null; then
    printf '\n# added by second-brain/install.sh\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "${HOME}/.zshrc"
  fi
  warn "Run 'source ~/.zshrc' (or open a new terminal) when this finishes."
  export PATH="${BIN_DIR}:${PATH}"
fi

# ------------------------------------------------------------- 2. the hooks

say "Wiring the capture hooks into Claude Code"
mkdir -p "$CLAUDE_DIR"
[ -f "$SETTINGS" ] && cp "$SETTINGS" "${SETTINGS}.bak-${STAMP}" && ok "backed up settings.json"

BRAIN_BIN="${BIN_DIR}/brain" python3 - "$SETTINGS" <<'PY'
import json, os, sys

path = sys.argv[1]
brain = os.environ["BRAIN_BIN"]

try:
    with open(path, encoding="utf-8") as fh:
        settings = json.load(fh)
except FileNotFoundError:
    settings = {}
except json.JSONDecodeError as exc:
    sys.exit(f"    settings.json is not valid JSON ({exc}). Fix it, then re-run.")

hooks = settings.setdefault("hooks", {})

# SessionStart  -> stdout becomes context, so the session opens already knowing.
# UserPromptSubmit -> every prompt lands in the day's note, verbatim.
# PostToolUse   -> which files this work touched, deduped per file per day.
# SessionEnd    -> carry the unfinished part forward. NOT Stop, which fires
#                  after every single reply and would log a heartbeat.
wanted = {
    "SessionStart":     {"matcher": "startup|resume|clear", "cmd": f"{brain} session-start"},
    "UserPromptSubmit": {"matcher": None,                   "cmd": f"{brain} prompt"},
    "PostToolUse":      {"matcher": "Edit|Write|NotebookEdit", "cmd": f"{brain} tool"},
    "SessionEnd":       {"matcher": None,                   "cmd": f"{brain} session-end"},
}

added = []
for event, spec in wanted.items():
    entries = hooks.setdefault(event, [])
    if any(spec["cmd"] in json.dumps(entry) for entry in entries):
        continue
    block = {"hooks": [{"type": "command", "command": spec["cmd"], "timeout": 15}]}
    if spec["matcher"]:
        block["matcher"] = spec["matcher"]
    entries.append(block)
    added.append(event)

tmp = path + ".tmp"
with open(tmp, "w", encoding="utf-8") as fh:
    json.dump(settings, fh, indent=2)
    fh.write("\n")
os.replace(tmp, path)
print("    ok   " + (f"added hooks: {', '.join(added)}" if added else "hooks already wired"))
PY

# ------------------------------------------------- 3. the standing instruction

say "Installing the memory contract into ~/.claude/CLAUDE.md"
BEGIN="<!-- BEGIN second-brain -->"
END="<!-- END second-brain -->"

if [ -f "$GLOBAL_MD" ] && grep -qF "$BEGIN" "$GLOBAL_MD"; then
  cp "$GLOBAL_MD" "${GLOBAL_MD}.bak-${STAMP}"
  python3 - "$GLOBAL_MD" "${HERE}/CLAUDE-global.md" "$BEGIN" "$END" <<'PY'
import re, sys
target, source, begin, end = sys.argv[1:5]
body = open(source, encoding="utf-8").read().strip()
text = open(target, encoding="utf-8").read()
text = re.sub(re.escape(begin) + r".*?" + re.escape(end),
              f"{begin}\n{body}\n{end}", text, flags=re.DOTALL)
open(target, "w", encoding="utf-8").write(text)
PY
  ok "refreshed the existing block (your other instructions untouched)"
else
  {
    printf '\n%s\n' "$BEGIN"
    cat "${HERE}/CLAUDE-global.md"
    printf '%s\n' "$END"
  } >> "$GLOBAL_MD"
  ok "appended to ${GLOBAL_MD}"
fi

[ "$HOOKS_ONLY" -eq 1 ] && { say "Done (hooks only)."; exit 0; }

# ------------------------------------------------------------- 4. Graphify

say "Graphify — structural index of the code"
if command -v graphify >/dev/null 2>&1; then
  ok "already installed: $(command -v graphify)"
else
  if command -v uv >/dev/null 2>&1; then
    uv tool install graphifyy && ok "installed via uv"
  elif command -v pipx >/dev/null 2>&1; then
    pipx install graphifyy && ok "installed via pipx"
  else
    warn "neither uv nor pipx found; falling back to pip --user"
    python3 -m pip install --user graphifyy || warn "pip install failed — see graphify.com/docs/install"
  fi
fi
if command -v graphify >/dev/null 2>&1; then
  graphify install && ok "registered the /graphify skill with the assistants it found"
fi

# ------------------------------------------------------- 5. the MCP servers

if [ "$DO_MCP" -eq 1 ] && command -v claude >/dev/null 2>&1; then
  say "Registering MCP servers with Claude Code"

  if command -v hermes >/dev/null 2>&1; then
    claude mcp add hermes -- hermes mcp serve 2>/dev/null \
      && ok "hermes" || warn "hermes already registered, or the add failed"
  else
    warn "hermes not on PATH — skipping. See second-brain/HERMES.md"
  fi

  # Figma's desktop server only exists while the app is open with Dev Mode's
  # MCP server toggled on; registering it now is still correct, it just stays
  # red in /mcp until Figma is running.
  claude mcp add --transport http figma-desktop http://127.0.0.1:3845/mcp 2>/dev/null \
    && ok "figma-desktop (needs Figma open with the Dev Mode MCP server enabled)" \
    || warn "figma-desktop already registered, or the add failed"

  # Canva is hosted, so unlike Figma's desktop server it needs nothing running
  # locally — just an OAuth approval the first time a tool is called.
  claude mcp add --transport http canva https://mcp.canva.com/mcp 2>/dev/null \
    && ok "canva (authenticate on first use)" \
    || warn "canva already registered, or the add failed"

  warn "n8n: register with your own instance URL and API key —"
  warn "     claude mcp add --transport http n8n https://<your-n8n-host>/mcp"
else
  [ "$DO_MCP" -eq 1 ] && warn "claude CLI not found — skipping MCP registration"
fi

# ---------------------------------------------------------------- 6. verify

say "Checking the result"
"${BIN_DIR}/brain" doctor || true

cat <<'EOF'

Next:
  1. source ~/.zshrc          (if the PATH note appeared above)
  2. cd <any project>
  3. brain init               creates ~/Obsidian/<project> and binds it here
  4. open that folder in Obsidian as a vault
  5. start Claude Code there — it will read the vault on the way in and
     write to it as it works, without being asked

EOF
