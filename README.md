# CM Marketplace

Plugin marketplace for the **Config Manager** project — a multi-repo Go ecosystem
for managing headless Debian/ARM devices (Raspberry Pi, UniFi CloudKey).

**Zero external dependencies.** All skills use built-in Copilot CLI agents
and PowerShell scripts. No Node.js, no MCP servers, no npm.

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
| **scaffold-plugin** | "create plugin", "new plugin" | Scaffolds a new CM plugin repo with all boilerplate (1,309 lines) |
| **cm-fleet-review** | "fleet review", "run fleet" | 10-agent multi-model code review with mandatory checklists |
| **cm-pr-lifecycle** | "create pr", "pr workflow" | Full PR cycle: build → fleet → fix → commit → push → PR → merge |
| **cm-release** | "release", "tag repos" | Cross-repo release with validation, tagging, and release notes |
| **cm-parity-check** | "parity check", "check parity" | TUI ↔ Web feature and security parity verification |
| **cm-pr-comments** | "triage comments", "pr feedback" | PR comment triage, risk assessment, and thread resolution |
| **cm-docs-sync** | "sync docs", "docs audit" | Cross-repo documentation and config consistency audit |

### PowerShell Scripts (6)

Helper scripts that skills invoke directly — no intermediary server needed.

| Script | Usage |
| --- | --- |
| `validate-repo.ps1` | Build + test + lint a single repo |
| `validate-all.ps1` | Validate all 5 repos |
| `repo-status.ps1` | Git branch, clean state, last tag for all repos |
| `tag-all.ps1` | Tag all repos in dependency order |
| `sync-deps.ps1` | Bump go.mod dependency across downstream repos |
| `project-board.ps1` | Add items and update status on GitHub project board |

### Custom Agents (2)

Installed at `~/.copilot/agents/` on first use.

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
├── plugins/
│   └── cm-dev-tools/                 # Plugin: CM development toolkit
│       ├── .claude-plugin/
│       │   └── plugin.json           # Plugin manifest
│       ├── skills/
│       │   ├── README.md             # Skill index with decision table
│       │   ├── scaffold-plugin/      # New plugin repo scaffolding
│       │   │   └── SKILL.md
│       │   ├── cm-fleet-review/      # 10-agent multi-model code review
│       │   │   └── SKILL.md
│       │   ├── cm-pr-lifecycle/      # Full PR cycle automation
│       │   │   └── SKILL.md
│       │   ├── cm-release/           # Cross-repo release workflow
│       │   │   └── SKILL.md
│       │   ├── cm-parity-check/      # TUI ↔ Web parity verification
│       │   │   └── SKILL.md
│       │   ├── cm-pr-comments/       # PR comment triage and resolution
│       │   │   └── SKILL.md
│       │   └── cm-docs-sync/         # Documentation consistency audit
│       │       └── SKILL.md
│       └── scripts/
│           ├── validate-repo.ps1     # Build + test + lint one repo
│           ├── validate-all.ps1      # Validate all 5 repos
│           ├── repo-status.ps1       # Git status across repos
│           ├── tag-all.ps1           # Tag repos in dependency order
│           ├── sync-deps.ps1         # Bump go.mod dependencies
│           └── project-board.ps1     # GitHub project board automation
├── README.md                         # This file
├── RELEASES.md                       # Version history
├── CONTRIBUTING.md                   # How to add plugins/skills
├── .gitignore
├── .editorconfig
└── .markdownlint.json
```

## Updating the Plugin

```powershell
# Remove cache and re-add to get latest
Remove-Item -Recurse -Force "$env:USERPROFILE\.copilot\marketplace-cache\msutara-cm-marketplace" -ErrorAction SilentlyContinue
copilot plugin marketplace add msutara/cm-marketplace
copilot plugin update cm-dev-tools@cm-marketplace
```

If update doesn't detect new version, do a clean reinstall:

```powershell
copilot plugin uninstall cm-dev-tools@cm-marketplace
copilot plugin install cm-dev-tools@cm-marketplace
```

## Prerequisites

- **GitHub Copilot CLI** or **Claude Code** installed
- **Go 1.24+** — for build/test/lint operations
- **golangci-lint v2** — for linting
- **gh CLI** — for PR and project board operations
- **PowerShell 7+** — for helper scripts
