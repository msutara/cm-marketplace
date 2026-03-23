# CM Marketplace — Release History

## [1.1.4] — 2026-03-23

### Fixed

- **MCP server fails to load in installed plugin context** — two compounding bugs:
  - Path resolution (`resolve(toolsDir, "..", "..", "..")`) assumed source repo
    layout (4 segments) but installed layout has only 3 segments, resolving to
    `installed-plugins/` instead of `cm-marketplace/`
  - No `package.json` or `node_modules/` in installed location — the plugin
    installer copies only the plugin subdirectory, not the parent repo's deps
- **Fix**: MCP runtime deps (`@modelcontextprotocol/sdk`, `zod`) now live in
  `tools/package.json` alongside the launcher; `createRequire` anchored at
  `toolsDir`; auto-installs deps on first run if `node_modules/` is missing
- Removed dead `dependencies` from root `package.json` (moved to `tools/`)
- Bumped MCP server version from 1.1.0 to 1.1.4

## [1.1.3] — 2026-03-22

### Changed

- **scaffold-plugin** skill rewrite addressing 9 gaps (2 CRITICAL):
  - S1: `Version()` now uses `var version = "dev"` + ldflags pattern instead of
    hardcoded `"0.1.0"`; test asserts `!= ""` instead of `!= "0.1.0"`
  - S2: Release workflow replaced — plugins are library packages, no standalone
    binary or `.deb`; uses `softprops/action-gh-release@v2` for lightweight
    tag-only releases
  - S3: `setup-go@v5` → `@v6` in CI and release workflows
  - S4: Added go.work registration step (Step 5.6)
  - S5: Added core Makefile/release.yml ldflags update step (Step 5.5)
  - S6: `go get @latest` → `@v0.1.0` (pinned version)
  - S7: CONTRIBUTING.md reads repo list from manifest instead of hardcoding
  - S8: `dep_order` inserts before UI repos instead of appending to end
  - S9: Added branch protection setup step (Step 10)
  - Updated verification checklist with all new steps
  - Removed nfpm.yaml template (plugins don't produce `.deb`)

- **cm-release** skill rewrite addressing 12 gaps (1 CRITICAL):
  - Multi-wave tagging (leaves → go.mod sync → core → go.mod sync → UI)
    replaces broken single-pass linear tagging
  - Phase 0 (auth check) added
  - Phase 2 (release scope) with selective tagging — skip chore-only repos
  - Phase 4 (go.mod sync) as mandatory step between tagging waves, using
    PR flow instead of direct push to main
  - Go module proxy wait with retry loop
  - Rich release notes with repo descriptions, What's New paragraphs,
    categorized changelogs, credits, and downloads table
  - Annotated tags with multi-line messages
  - ldflags verification step
  - Release recovery procedure for partially-botched releases
  - Orphan draft release cleanup after tag/release redo
  - 12 safety rules (up from 8)

- **cm-fleet-review** fixes (2 LOW gaps):
  - F1: Clarified minimum fleet (5 agents, Group A) vs full fleet (11 agents)
    with guidance on when to use each; description updated from "11-agent" to
    "5–11 agent"
  - F2: Added Windows/PowerShell operational notes (parallel golangci-lint
    conflicts, `--body-file` workaround)

- **cm-pr-lifecycle** fixes (3 LOW gaps):
  - P1: Added `gh auth status` check before PR creation (Phase 7)
  - P2: Changed `--body` to `--body-file` to avoid Windows/PowerShell escaping
  - P3: Added `GOWORK=off` to Phase 1 build/test for CI-realistic validation

- **cm-parity-check** fix (1 MEDIUM gap):
  - PC1: Replaced hardcoded `file.go:function()` references with dynamic
    `grep -rn` discovery patterns — prevents stale refs when code is refactored

- **cm-docs-sync** fix (1 MEDIUM gap + cross-cutting X1):
  - D1/X1: Added Step 5 "Skill Template Drift Detection" — compares
    version-pinned references in skill templates (setup-go@, golangci-lint@,
    etc.) against actual CI configs to catch skill maintenance drift

- **Documentation synced**: skills README, plugin README, root README,
  CMReviewer.agent.md all updated to match new skill descriptions

- **Metadata**: version bumped to 1.1.3 across package.json, package-lock.json,
  marketplace.json, and plugin.json; plugin.json `agents` field changed from
  directory path to explicit file array

## [1.1.2] — 2026-03-22

### Fixed

- MCP server launcher failed to start (error 3200) — `@modelcontextprotocol/sdk`
  1.27.1 ships without a root CJS entry point (`dist/cjs/index.js`); changed
  dependency check to resolve `@modelcontextprotocol/sdk/server` subpath instead

## [1.1.1] — 2026-03-22

### Changed

- Skill prompts now reference `.cm/project.json` manifest instead of hardcoded
  repo names and project board commands (cm-parity-check, cm-pr-lifecycle,
  cm-pr-comments, cm-release); scaffold-plugin version placeholder replaced
  with dynamic tag detection
- README notes repos are defined in manifest

## [1.1.0] — 2026-03-22

### Added

- **MCP server** (`cm-repos`) — stdio MCP server wrapping bash scripts for
  structured tool discovery by AI agents:
  - 8 tools: `cm_repo_status`, `cm_validate_repo`, `cm_validate_all`,
    `cm_sync_deps`, `cm_tag_repo`, `cm_tag_all`, `cm_project_add`,
    `cm_project_status`
  - Auto-discovery via `.mcp.json` in plugin root
  - Bootstrap launcher with dependency check and actionable install instructions
  - Per-tool timeouts, Windows Git Bash support, `CM_REPO_BASE` auto-detection
- **`--json` flag** on 6 bash scripts — structured JSON output for programmatic
  consumption (repo-status, validate-repo, validate-all, project-board,
  tag-all, sync-deps)
- **Production dependencies**: `@modelcontextprotocol/sdk` 1.27.1, `zod` 4.3.6

## [1.0.0] — 2026-03-20

### Added

- **cm-dev-tools plugin** — full development toolkit for Config Manager:
  - 7 workflow skills:
    - `scaffold-plugin` — new CM plugin repo scaffolding
    - `cm-fleet-review` — 11-agent multi-model code review with mandatory checklists
    - `cm-pr-lifecycle` — full PR cycle: build → fleet → fix → commit → push → PR → merge
    - `cm-release` — cross-repo release with validation and tagging
    - `cm-parity-check` — TUI ↔ Web feature and security parity verification
    - `cm-pr-comments` — PR comment triage, risk assessment, thread resolution
    - `cm-docs-sync` — cross-repo documentation consistency audit
  - 7 bash helper scripts (validate, status, tag, sync, project board, init)
  - 2 custom agents (CMDeveloper, CMReviewer)

### Design Decisions

- **No AVD coupling** — built on standard CLI agent platform capabilities (Copilot CLI / Claude Code)
- Skills use bash scripts, custom agents, and built-in CLI agent types
- Derived from analysis of 112 session checkpoints identifying the most
  repeated workflows (fleet review in 51%, PR lifecycle in 91%,
  build/test/lint in 99% of checkpoints)
