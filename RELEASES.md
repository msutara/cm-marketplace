# CM Marketplace — Release History

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
