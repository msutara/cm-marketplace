# cm-dev-tools

Development toolkit plugin for the Config Manager project. Works with
GitHub Copilot CLI and Claude Code.

## Contents

### Skills (7)

| Skill | What It Does |
| --- | --- |
| **scaffold-plugin** | Scaffolds a new CM plugin repo with all boilerplate |
| **cm-fleet-review** | 10-agent multi-model code review |
| **cm-pr-lifecycle** | Full PR cycle: build → fleet → fix → commit → push → PR → merge |
| **cm-release** | Cross-repo release with validation, tagging, and release notes |
| **cm-parity-check** | TUI ↔ Web feature and security parity verification |
| **cm-pr-comments** | PR comment triage, risk assessment, and thread resolution |
| **cm-docs-sync** | Cross-repo documentation and config consistency audit |

### Bash Scripts (6)

| Script | Usage |
| --- | --- |
| `validate-repo.sh` | Build + test + lint a single repo |
| `validate-all.sh` | Validate all repos in sequence |
| `repo-status.sh` | Git branch, clean state, last tag for all repos |
| `tag-all.sh` | Tag all repos in dependency order |
| `sync-deps.sh` | Bump go.mod dependency across downstream repos |
| `project-board.sh` | Add items and update status on GitHub project board |

### Custom Agents (2)

| Agent | Purpose |
| --- | --- |
| **CMDeveloper** | Full-stack CM development with embedded project knowledge |
| **CMReviewer** | Code review specialist with fleet config and false positive suppression |

## Install

```bash
# GitHub Copilot CLI
copilot plugin marketplace add msutara/cm-marketplace
copilot plugin install cm-dev-tools@cm-marketplace

# Claude Code
claude plugin marketplace add msutara/cm-marketplace
claude plugin install cm-dev-tools@cm-marketplace
```

## Prerequisites (for target CM repos)

- **Go 1.24+** — build/test/lint
- **golangci-lint v2** — Go linting
- **gh CLI** — PR and project board operations
- **jq** — JSON processing in project-board script
- **bash 4+** — required for project-board script (associative arrays)
