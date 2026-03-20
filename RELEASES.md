# CM Marketplace — Release History

## [1.0.0] — 2026-03-20

### Added

- **cm-dev-tools plugin** — full development toolkit for Config Manager:
  - 7 workflow skills:
    - `scaffold-plugin` — new CM plugin repo scaffolding (1,309 lines)
    - `cm-fleet-review` — 10-agent multi-model code review with mandatory checklists
    - `cm-pr-lifecycle` — full PR cycle: build → fleet → fix → commit → push → PR → merge
    - `cm-release` — cross-repo release with validation and tagging
    - `cm-parity-check` — TUI ↔ Web feature and security parity verification
    - `cm-pr-comments` — PR comment triage, risk assessment, thread resolution
    - `cm-docs-sync` — cross-repo documentation consistency audit
  - 6 bash helper scripts (validate, status, tag, sync, project board)
  - 2 custom agents (CMDeveloper, CMReviewer)

### Design Decisions

- **Zero external dependencies** — no Node.js runtime, no MCP servers
- Skills use built-in Copilot CLI agent types and bash scripts
- Derived from analysis of 112 session checkpoints identifying the most
  repeated workflows (fleet review in 51%, PR lifecycle in 91%,
  build/test/lint in 99% of checkpoints)
