#!/usr/bin/env bash
# Cloud Agent install script for the Claude Code Source Snapshot repo.
#
# Idempotent bootstrap for all three workspaces:
#   - root   : archived Claude Code CLI snapshot (Bun / TypeScript)
#   - mcp-server : Claude Code Explorer MCP server (Node / TypeScript) — primary dev surface
#   - web    : Next.js chat UI (Node / TypeScript)
#
# Safe to run repeatedly. Must terminate; no long-running processes start here.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# ---------------------------------------------------------------------------
# 1. Ensure Bun is available (root snapshot requires engines.bun >= 1.1.0).
#    Installed to $HOME/.bun and symlinked into a persistent PATH dir so it is
#    visible from install, start, terminals, and interactive shells.
# ---------------------------------------------------------------------------
if ! command -v bun >/dev/null 2>&1; then
  export BUN_INSTALL="$HOME/.bun"
  curl -fsSL https://bun.sh/install | bash
  sudo ln -sf "$BUN_INSTALL/bin/bun" /usr/local/bin/bun
fi
echo "bun $(bun --version)"
echo "node $(node --version)"

# ---------------------------------------------------------------------------
# 2. Root: archived CLI snapshot dependencies (Bun lockfile).
# ---------------------------------------------------------------------------
bun install --frozen-lockfile

# ---------------------------------------------------------------------------
# 3. MCP explorer server: install + compile to dist/ (the primary contribution
#    surface; buildable and runnable with no secrets).
# ---------------------------------------------------------------------------
(cd mcp-server && npm ci && npm run build)

# ---------------------------------------------------------------------------
# 4. Web chat UI dependencies.
# ---------------------------------------------------------------------------
(cd web && npm ci)

echo "install.sh complete"
