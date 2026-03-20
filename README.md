# CM Marketplace

Plugin marketplace for the **Config Manager** project — a multi-repo Go ecosystem
for managing headless Debian/ARM devices (Raspberry Pi, UniFi CloudKey).

**Zero external dependencies.** All skills use built-in Copilot CLI agents
and bash scripts. No Node.js runtime, no MCP servers.

## Quick Start

### GitHub Copilot CLI

```bash
copilot plugin marketplace add msutara/cm-marketplace
copilot plugin install cm-dev-tools@cm-marketplace
```

### Claude Code

```bash
claude plugin marketplace add msutara/cm-marketplace
claude plugin install cm-dev-tools@cm-marketplace
```

## Available Plugins

| Plugin | Description | Skills | Scripts | Agents |
| --- | --- | --- | --- | --- |
| [`cm-dev-tools`](plugins/cm-dev-tools/) | Full development toolkit for Config Manager | 7 | 6 | 2 |

## What You Get

### Skills (7)

| Skill | Trigger | What It Does |
| --- | --- | --- |
| **scaffold-plugin** | "create plugin", "new plugin" | Scaffolds a new CM plugin repo with all boilerplate |
| **cm-fleet-review** | "fleet review", "run fleet" | 10-agent multi-model code review with mandatory checklists |
| **cm-pr-lifecycle** | "create pr", "pr workflow" | Full PR cycle: build → fleet → fix → commit → push → PR → merge |
| **cm-release** | "release", "tag repos" | Cross-repo release with validation, tagging, and release notes |
| **cm-parity-check** | "parity check", "check parity" | TUI ↔ Web feature and security parity verification |
| **cm-pr-comments** | "triage comments", "pr feedback" | PR comment triage, risk assessment, and thread resolution |
| **cm-docs-sync** | "sync docs", "docs audit" | Cross-repo documentation and config consistency audit |

### Bash Scripts (6)

Helper scripts that skills invoke directly — no intermediary server needed.
All scripts use `${CM_REPO_BASE:-$HOME/repo}` for the repo base path.

| Script | Usage |
| --- | --- |
| `validate-repo.sh` | Build + test + lint a single repo |
| `validate-all.sh` | Validate all 5 repos |
| `repo-status.sh` | Git branch, clean state, last tag for all repos |
| `tag-all.sh` | Tag all repos in dependency order |
| `sync-deps.sh` | Bump go.mod dependency across downstream repos |
| `project-board.sh` | Add items and update status on GitHub project board |

### Custom Agents (2)

Source files are in `plugins/cm-dev-tools/agents/`. To install, copy to `~/.copilot/agents/`:

```bash
cp plugins/cm-dev-tools/agents/*.agent.md ~/.copilot/agents/
```

| Agent | Purpose |
| --- | --- |
| **CMDeveloper** | Full-stack CM development with embedded project knowledge |
| **CMReviewer** | Code review specialist with fleet config and false positive suppression |

## Repos Managed

| Repo | Role |
| --- | --- |
| [`config-manager-core`](https://github.com/msutara/config-manager-core) | Central service, plugin registry, scheduler, API |
| [`cm-plugin-network`](https://github.com/msutara/cm-plugin-network) | Network interface configuration |
| [`cm-plugin-update`](https://github.com/msutara/cm-plugin-update) | OS/package update management |
| [`config-manager-tui`](https://github.com/msutara/config-manager-tui) | Terminal UI (Bubble Tea) |
| [`config-manager-web`](https://github.com/msutara/config-manager-web) | Web UI (htmx + Go templates) |

## Repository Structure

```text
cm-marketplace/
├── .claude-plugin/
│   └── marketplace.json              # Marketplace manifest
├── .github/
│   ├── CODEOWNERS                    # Default reviewers
│   ├── copilot-instructions.md       # AI agent context for this repo
│   └── pull_request_template.md      # PR checklist
├── plugins/
│   └── cm-dev-tools/                 # Plugin: CM development toolkit
│       ├── .claude-plugin/
│       │   └── plugin.json           # Plugin manifest
│       ├── agents/
│       │   ├── CMDeveloper.agent.md  # Full-stack CM dev agent
│       │   └── CMReviewer.agent.md   # Code review fleet agent
│       ├── skills/
│       │   ├── README.md             # Skill index with decision table
│       │   ├── scaffold-plugin/
│       │   │   └── SKILL.md
│       │   ├── cm-fleet-review/
│       │   │   └── SKILL.md
│       │   ├── cm-pr-lifecycle/
│       │   │   └── SKILL.md
│       │   ├── cm-release/
│       │   │   └── SKILL.md
│       │   ├── cm-parity-check/
│       │   │   └── SKILL.md
│       │   ├── cm-pr-comments/
│       │   │   └── SKILL.md
│       │   └── cm-docs-sync/
│       │       └── SKILL.md
│       └── scripts/
│           ├── validate-repo.sh      # Build + test + lint one repo
│           ├── validate-all.sh       # Validate all 5 repos
│           ├── repo-status.sh        # Git status across repos
│           ├── tag-all.sh            # Tag repos in dependency order
│           ├── sync-deps.sh          # Bump go.mod dependencies
│           └── project-board.sh      # GitHub project board automation
├── README.md                         # This file
├── RELEASES.md                       # Version history
├── CONTRIBUTING.md                   # How to add plugins/skills
├── package.json                      # Lint tooling (markdownlint only)
├── .gitignore
├── .gitattributes
├── .editorconfig
└── .markdownlint.json
```

## Before Committing

1. **Lint** — `npm run lint` (markdownlint must pass)
2. **Fix** — `npm run lint:fix` for auto-fixable issues
3. **Verify JSON** — marketplace.json and plugin.json must be valid

## Updating the Plugin

```bash
# Remove cache and re-add to get latest
rm -rf ~/.copilot/marketplace-cache/msutara-cm-marketplace
copilot plugin marketplace add msutara/cm-marketplace
copilot plugin update cm-dev-tools@cm-marketplace
```

If update doesn't detect new version, do a clean reinstall:

```bash
copilot plugin uninstall cm-dev-tools@cm-marketplace
copilot plugin install cm-dev-tools@cm-marketplace
```

## Prerequisites

- **GitHub Copilot CLI** or **Claude Code** installed
- **Go 1.24+** — for build/test/lint operations
- **golangci-lint v2** — for linting
- **gh CLI** — for PR and project board operations
- **bash** — for helper scripts (native on Linux/macOS, Git Bash on Windows)
- **jq** — for JSON processing in project-board script
- **Node.js 20+** — for markdownlint-cli2 (lint only, not runtime)
