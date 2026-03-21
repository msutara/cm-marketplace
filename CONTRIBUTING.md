# Contributing to CM Marketplace

This guide explains how to add new plugins or skills to the marketplace.

## Adding a New Plugin

### 1. Create the plugin directory

```txt
plugins/<your-plugin-name>/
├── .claude-plugin/
│   └── plugin.json           # Required: plugin manifest
├── README.md                 # Required: plugin documentation
├── skills/                   # Required: at least one skill
│   ├── README.md
│   └── <skill-name>/
│       └── SKILL.md
└── scripts/                  # Optional: bash helper scripts
    └── *.sh
```

### 2. Create the plugin manifest

Create `.claude-plugin/plugin.json`:

```json
{
  "name": "my-plugin",
  "version": "1.0.0",
  "description": "What this plugin provides",
  "skills": "./skills/",
  "agents": "./agents/"
}
```

> The `agents` field is optional. Omit it if the plugin does not ship custom agents.

### 3. Add skills

Skills are reusable investigation or workflow protocols that AI agents can execute. Each skill lives in its own directory under `skills/`:

```txt
plugins/<your-plugin-name>/
└── skills/
    └── <skill-name>/
        └── SKILL.md              # Required: skill definition
```

A `SKILL.md` file uses YAML front matter for metadata and markdown for the execution protocol:

```markdown
---
name: my-skill-name
description: >
  One-paragraph description of what the skill does and when to use it.
  Include trigger phrases that should activate this skill.
---

# Skill Title

## Input

What parameters the skill accepts.

## Execution Protocol

Step-by-step instructions the agent follows.

## Output Format

How to present results.
```

**Skill guidelines:**

- One skill per directory — the directory name should match the `name` in front matter.
- Use `{PLACEHOLDER}` syntax for dynamic values in templates.
- Include column casing warnings where applicable.

### 4. Add bash scripts (optional)

Scripts go in `plugins/<plugin-name>/scripts/`. Conventions:

- Include a usage comment at the top of the file
- Use `set -euo pipefail` by default for strict error handling; omit `-e` only when you intentionally need to continue after failures (e.g., to accumulate results) and document the reason in a comment
- Use `${CM_REPO_BASE:-$HOME/repo}` for the repo base path where applicable (scripts that take an explicit path argument, like `validate-repo.sh`, are exempt)
- Prefer structured, parseable output where practical (e.g., a consistent format or optional `--json` flag); human-oriented summaries are fine for interactive use
- Handle errors gracefully with clear messages to stderr
- Use `✅` / `❌` / `⚠️` icons for scannable human output

### 5. Register in the marketplace

Add your plugin to the `plugins` array in `.claude-plugin/marketplace.json`:

```json
{
  "name": "my-plugin",
  "source": "./plugins/my-plugin",
  "description": "What this plugin does",
  "version": "1.0.0"
}
```

### 6. Update the root README

Add a row to the **Available Plugins** table in `README.md`.

### 7. Verify

Run the full lint suite before pushing:

```bash
npm run lint:all
```

This checks markdown with markdownlint.

## Adding a Custom Agent

Agent files go in `~/.copilot/agents/` as `<Name>.agent.md`.

Format:

```markdown
---
description: 'One-line description of the agent'
---

# Agent Name

## Purpose
...

## When to Use
...

## Knowledge
...
```

## Conventions

- **Plugin names** — lowercase, kebab-case (e.g., `cm-dev-tools`).
- **Skill names** — lowercase, kebab-case matching the directory name.
- **Script names** — lowercase, kebab-case `.sh` files with `#!/usr/bin/env bash` shebang.
- **No secrets** — never commit credentials, connection strings, or tokens.
- **Node.js 20+** — required for markdownlint-cli2 0.20.0.

## Version Bumping

When releasing a new version:

1. Update `plugins/<plugin>/plugin.json` version
2. Update `.claude-plugin/marketplace.json` version
3. Add entry to `RELEASES.md`
4. Commit, tag with `v{VERSION}`, push
