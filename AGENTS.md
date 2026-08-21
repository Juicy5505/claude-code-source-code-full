# AGENTS.md

General agent operating guidance lives in [`agent.md`](agent.md). Standard commands
are documented in each project's manifest and docs — see root [`package.json`](package.json),
[`CONTRIBUTING.md`](CONTRIBUTING.md), and [`mcp-server/README.md`](mcp-server/README.md).

## Cursor Cloud specific instructions

This repo is an **archived, partially-complete source snapshot** of the Claude Code CLI
plus two supporting sub-projects. Treat the snapshot as read-only (see `CONTRIBUTING.md`:
`src/` should not be changed). The environment update script already refreshes all
dependencies on startup (`bun install` at the root, `npm install` in `mcp-server/` and
`web/`), and **Bun is preinstalled and on `PATH`** (the root project's package manager).

There are three independent sub-projects. None imports another at runtime.

### 1. `mcp-server/` — Claude Code Explorer MCP server (the one product that fully runs)

Node/Express MCP server that browses the `src/` snapshot. No secrets required. This is the
actively-developed, publishable product — prefer it for end-to-end verification.

- Dev (STDIO, the primary command, also what `.mcp.json` uses): `npm run dev` (`npx tsx src/index.ts`). `SRC_ROOT` defaults to `/workspace/src` in dev mode.
- Build: `npm run build` (`tsc`). Health check when running HTTP: `GET /health`.
- Dev HTTP transport: `PORT=<port> npx tsx src/http.ts` → endpoints `/mcp` (Streamable HTTP), `/sse` + `/messages` (legacy SSE), `/health`. Default port is `3000`.
- **Gotcha — built entrypoint paths:** `tsconfig.json` uses `rootDir: "."`, so `tsc` emits `dist/src/index.js` and `dist/src/http.js`, **not** `dist/index.js`/`dist/http.js`. Therefore `npm start`, `npm run start:http`, and the `dist/index.js` path in the root `.mcp.json` are wrong as written. Run `node dist/src/index.js` / `node dist/src/http.js`, or just use `npm run dev`.
- **Gotcha — built server `SRC_ROOT`:** for the *built* server the default `SRC_ROOT` resolves to `mcp-server/src` (wrong) because of the same nesting; set `CLAUDE_CODE_SRC_ROOT=/workspace/src` when running `node dist/src/http.js`. Dev mode (`tsx`) resolves it correctly with no env var.

### 2. Root CLI (`/`, `src/`) — archived Claude Code snapshot

Bun + esbuild TUI. The snapshot is **intentionally incomplete**, so it does not fully build/run.

- Dev run: `bun scripts/dev.ts <args>`. Only the zero-import fast path works headlessly, e.g. `bun scripts/dev.ts --version` → `0.0.0-leaked (Claude Code)`. `--help`/REPL load modules that are missing from the snapshot.
- Full build (`bun run build` / `bun run build:prod`) **fails**: ~40 undeclared npm packages (`@aws-sdk/*`, `@opentelemetry/exporter-*`, `google-auth-library`, `jsonc-parser`, …) and dozens of omitted internal modules (`assistant/`, `proactive/`, `services/compact/*`, `claude-api/*.md`, …). This is a property of the snapshot, not a fixable env issue — do not add these or edit `src/`.
- Lint (`bun run lint` = `biome check src/`) and typecheck (`bun run typecheck` = `tsc --noEmit`) **execute** but report thousands of pre-existing issues. The GitHub CI workflow is deliberately disabled for exactly this reason (see `.github/workflows/ci.yml`). There are no automated tests wired up (`scripts/test-*.ts` are manual helpers; there is no `test` script).

### 3. `web/` — Next.js chat UI (does NOT run from this snapshot)

`npm install` succeeds, but the app cannot render because of missing snapshot pieces:

- `next.config.ts` requires Next ≥15, but `package.json` pins `next@^14` (Next 14 throws on a `.ts` config). Workaround if you must run it: add a `next.config.mjs` (Next resolves `.js`/`.mjs` before `.ts`).
- `app/layout.tsx` loads local fonts `public/fonts/JetBrainsMono-{Regular,Medium}.woff2` that are absent.
- `components/layout/Sidebar.tsx` (always rendered) imports source components that do not exist: `./ChatHistory`, `./FileExplorer`, `./QuickActions` (also `components/collaboration/AnnotationBadge.tsx` → `./AnnotationThread`). Rendering the UI would require reconstructing this missing product source.
- Chat also proxies to an external backend at `NEXT_PUBLIC_API_URL` (default `http://localhost:3001`) that is not part of this repo.
- Lint/typecheck: `npm run lint` (`next lint`) and `npm run type-check` (`tsc --noEmit`).

### Cross-cutting notes

- Ports: the MCP HTTP server and `web` dev server both default to `3000` — pick a different `PORT` if running both.
- `web/.next/` and `web/next-env.d.ts` are **not** git-ignored (there is no `web/.gitignore`), so running `next` leaves untracked files behind.
