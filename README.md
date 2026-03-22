# CM Marketplace

Plugin marketplace for the **Config Manager** project — workflow skills,
bash helper scripts, and custom agents for Copilot CLI and Claude Code.

Built on standard **CLI agent platform** capabilities — skills, agents,
and bash scripts. No AVD or enterprise dependencies.

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
| [`cm-dev-tools`](plugins/cm-dev-tools/) | Full development toolkit for Config Manager | 7 | 7 | 2 |

## What You Get

### Skills (7)

| Skill | Trigger | What It Does |
| --- | --- | --- |
| **scaffold-plugin** | "create plugin", "new plugin" | Scaffolds a new CM plugin repo with all boilerplate |
| **cm-fleet-review** | "fleet review", "run fleet" | 11-agent multi-model code review with mandatory checklists |
| **cm-pr-lifecycle** | "create pr", "pr workflow" | Full PR cycle: build → fleet → fix → commit → push → PR → merge |
| **cm-release** | "release", "tag repos" | Cross-repo release with validation, tagging, and release notes |
| **cm-parity-check** | "parity check", "check parity" | TUI ↔ Web feature and security parity verification |
| **cm-pr-comments** | "triage comments", "pr feedback" | PR comment triage, risk assessment, and thread resolution |
| **cm-docs-sync** | "sync docs", "docs audit" | Cross-repo documentation and config consistency audit |

### Bash Scripts (7)

Helper scripts that skills invoke directly — no intermediary server needed.
Scripts read project context (repos, owner, board IDs) from
`$CM_REPO_BASE/.cm/project.json` via a shared library.
All scripts (except init-project.sh) support `--json` for structured output.

| Script | Usage |
| --- | --- |
| `init-project.sh` | Generate the project manifest interactively |
| `validate-repo.sh` | Build + test + lint a single repo |
| `validate-all.sh` | Validate all repos from manifest |
| `repo-status.sh` | Git branch, clean state, last tag for all repos |
| `tag-all.sh` | Tag all repos in dependency order from manifest |
| `sync-deps.sh` | Bump go.mod dependency across downstream repos |
| `project-board.sh` | Add items and update status on GitHub project board |

### MCP Server (`cm-repos`)

Stdio MCP server that wraps the bash scripts above for structured AI agent
discovery. Auto-registered via `.mcp.json` in the plugin root.

| MCP Tool | Description |
| --- | --- |
| `cm_repo_status` | Git branch, clean state, and last tag |
| `cm_validate_repo` | Build + test + lint a single repo |
| `cm_validate_all` | Validate all manifest repos |
| `cm_sync_deps` | Bump a go.mod dependency across repos |
| `cm_tag_repo` | Tag all repos at a version (single-repo not yet supported) |
| `cm_tag_all` | Tag all repos in dependency order |
| `cm_project_add` | Add an item to the project board |
| `cm_project_status` | Update item status on the project board |

### Custom Agents (2)

Source files are in `plugins/cm-dev-tools/agents/`. To install, copy to `~/.copilot/agents/`:

```bash
cp plugins/cm-dev-tools/agents/*.agent.md ~/.copilot/agents/
```

| Agent | Purpose |
| --- | --- |
| **CMDeveloper** | Full-stack CM development with embedded project knowledge |
| **CMReviewer** | Code review specialist with fleet config and false positive suppression |

## Project Manifest

Scripts and skills read project context from `$CM_REPO_BASE/.cm/project.json`.
This file defines repos, owner, dependency order, and project board IDs.

Generate it interactively:

```bash
./plugins/cm-dev-tools/scripts/init-project.sh
```

Or copy the template and edit:

```bash
mkdir -p "${CM_REPO_BASE:-$HOME/repo}/.cm"
cp docs/project.example.json "${CM_REPO_BASE:-$HOME/repo}/.cm/project.json"
# Edit with your values
```

See [`docs/project.example.json`](docs/project.example.json) for the full schema.

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
│   ├── dependabot.yml                # Automated dependency updates
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.md             # Bug report template
│   │   ├── config.yml                # Issue template chooser config
│   │   └── feature_request.md        # Feature request template
│   ├── pull_request_template.md      # PR checklist
│   └── workflows/
│       └── ci.yml                    # CI: markdownlint + shellcheck + biome
├── plugins/
│   └── cm-dev-tools/                 # Plugin: CM development toolkit
│       ├── .claude-plugin/
│       │   └── plugin.json           # Plugin manifest
│       ├── README.md                 # Plugin documentation
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
│       ├── scripts/
│       │   ├── lib/
│       │   │   └── load-project.sh     # Shared: reads project.json manifest
│       │   ├── init-project.sh         # Generate project.json interactively
│       │   ├── validate-repo.sh        # Build + test + lint one repo
│       │   ├── validate-all.sh         # Validate all repos from manifest
│       │   ├── repo-status.sh          # Git status across repos
│       │   ├── tag-all.sh              # Tag repos in dependency order
│       │   ├── sync-deps.sh            # Bump go.mod dependencies
│       │   └── project-board.sh        # GitHub project board automation
│       ├── tools/
│       │   ├── ensure-prerequisites.mjs # Preflight CLI tool checker
│       │   ├── cm-repos-server.mjs     # MCP server (8 tools)
│       │   └── cm-repos-launcher.mjs   # MCP bootstrap launcher
│       └── .mcp.json                   # MCP server auto-registration
├── docs/
│   └── project.example.json           # Template for project manifest
├── LICENSE                           # GPL-3.0
├── README.md                         # This file
├── RELEASES.md                       # Version history
├── CONTRIBUTING.md                   # How to add plugins/skills
├── package.json                      # Dependencies (MCP SDK, Zod, markdownlint, Biome)
├── package-lock.json                 # Locked dependency versions
├── .editorconfig                     # Editor formatting rules
├── .gitattributes                    # LF enforcement for *.sh
├── .gitignore                        # Ignored files
└── .markdownlint.json                # Markdownlint configuration
```

## Before Committing

1. **Lint** — `npm run lint:all` (markdownlint + Biome JS must pass)
2. **Fix** — `npm run lint:fix` / `npm run lint:js:fix` for auto-fixable issues
3. **Verify JSON** — marketplace.json and plugin.json must be valid

## Updating the Plugin

### GitHub Copilot CLI

```bash
rm -rf ~/.copilot/marketplace-cache/msutara-cm-marketplace
copilot plugin marketplace add msutara/cm-marketplace
copilot plugin update cm-dev-tools@cm-marketplace
```

### Claude Code

```bash
rm -rf ~/.claude/marketplace-cache/msutara-cm-marketplace
claude plugin marketplace add msutara/cm-marketplace
claude plugin update cm-dev-tools@cm-marketplace
```

If update doesn't detect new version, do a clean reinstall:

```bash
# Replace 'copilot' with 'claude' for Claude Code
copilot plugin uninstall cm-dev-tools@cm-marketplace
copilot plugin install cm-dev-tools@cm-marketplace
```

## Prerequisites

### For this marketplace repo

- **GitHub Copilot CLI** or **Claude Code** — either AI platform works (not checked by the prereq tool)
- **git 2.30+** — for version control and PR workflows
- **Node.js 20+** — for markdownlint-cli2 and Biome linting
- **bash 4+** — for helper scripts (native on Linux, `brew install bash` on macOS, Git Bash on Windows)
- **gh CLI** — for PR and project board scripts
- **jq** — for reading project manifest and JSON processing
- **shellcheck** — for CI shell linting (on Windows, install via [Scoop](https://scoop.sh))

Run `node plugins/cm-dev-tools/tools/ensure-prerequisites.mjs` to verify the developer tools above.
Add `--install` to auto-install missing tools.

### For target CM repos (used by skills at runtime)

- **Go 1.24+** — build/test/lint operations
- **golangci-lint v2** — Go linting
