# cm-dev-tools

Development toolkit plugin for the Config Manager project. Works with
GitHub Copilot CLI and Claude Code.

## Contents

### Skills (7)

| Skill | What It Does |
| --- | --- |
| **scaffold-plugin** | Scaffolds a new CM plugin repo with all boilerplate |
| **cm-fleet-review** | 11-agent multi-model code review |
| **cm-pr-lifecycle** | Full PR cycle: build → fleet → fix → commit → push → PR → merge |
| **cm-release** | Cross-repo release with validation, tagging, and release notes |
| **cm-parity-check** | TUI ↔ Web feature and security parity verification |
| **cm-pr-comments** | PR comment triage, risk assessment, and thread resolution |
| **cm-docs-sync** | Cross-repo documentation and config consistency audit |

### Bash Scripts (7)

| Script | Usage |
| --- | --- |
| `validate-repo.sh` | Build + test + lint a single repo |
| `validate-all.sh` | Validate all repos in sequence |
| `repo-status.sh` | Git branch, clean state, last tag for manifest repos |
| `tag-all.sh` | Tag manifest repos in manifest `dep_order` |
| `sync-deps.sh` | Bump go.mod dependency across manifest downstream repos |
| `project-board.sh` | Add items and update status on manifest-configured project board |
| `init-project.sh` | Interactive `.cm/project.json` manifest generator |

### Custom Agents (2)

| Agent | Purpose |
| --- | --- |
| **CMDeveloper** | Full-stack CM development with embedded project knowledge |
| **CMReviewer** | Code review specialist with fleet config and false positive suppression |

### Tools (3)

| Tool | Purpose |
| --- | --- |
| `ensure-prerequisites.mjs` | Preflight check — verifies all required CLIs are installed and meet minimum versions |
| `cm-repos-server.mjs` | MCP stdio server exposing 8 tools for multi-repo operations |
| `cm-repos-launcher.mjs` | Bootstrap launcher — checks deps and starts the MCP server |

### MCP Server (`cm-repos`)

Auto-discovered via `.mcp.json`. Exposes bash scripts as structured MCP tools:

| MCP Tool | Wraps | Description |
| --- | --- | --- |
| `cm_repo_status` | repo-status.sh | Git branch, clean state, and last tag |
| `cm_validate_repo` | validate-repo.sh | Build + test + lint a single repo |
| `cm_validate_all` | validate-all.sh | Validate all manifest repos |
| `cm_sync_deps` | sync-deps.sh | Bump a go.mod dependency across repos |
| `cm_tag_repo` | *(not yet implemented)* | Tag a single repo (fails fast — use `cm_tag_all` instead) |
| `cm_tag_all` | tag-all.sh | Tag all repos in dependency order |
| `cm_project_add` | project-board.sh | Add an item to the project board |
| `cm_project_status` | project-board.sh | Update item status on the project board |

All scripts except `init-project.sh` support `--json` for structured output (used by the MCP server internally).

## Install

```bash
# GitHub Copilot CLI
copilot plugin marketplace add msutara/cm-marketplace
copilot plugin install cm-dev-tools@cm-marketplace

# Claude Code
claude plugin marketplace add msutara/cm-marketplace
claude plugin install cm-dev-tools@cm-marketplace
```

## Prerequisites

### For this plugin's scripts and skills

- **Node.js 20+** — required for repo tooling (npm lint scripts) and the `ensure-prerequisites.mjs` checker
- **bash 4+** — required for all manifest-driven scripts (associative arrays)
- **jq** — JSON processing (required by all manifest-driven scripts)
- **gh CLI** — PR and project board operations
- **git** — required by all scripts
- **shellcheck** — for CI shell linting

From the repository root, run `node plugins/cm-dev-tools/tools/ensure-prerequisites.mjs` to check all at once.
Add `--install` to auto-install missing tools.

### For target CM repos (used by skills at runtime)

- **Go 1.24+** — build/test/lint
- **golangci-lint v2** — Go linting
