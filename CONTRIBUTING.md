# Contributing to CM Marketplace

This guide explains how to add new plugins or skills to the marketplace.

## Adding a New Skill to cm-dev-tools

### 1. Create the skill directory

```text
plugins/cm-dev-tools/skills/<skill-name>/
└── SKILL.md
```

### 2. Write the SKILL.md

Every skill file uses YAML frontmatter + markdown body:

```markdown
---
name: my-skill-name
description: >
  What this skill does. Include trigger phrases so the agent
  knows when to activate: "trigger one", "trigger two", etc.
---

# Skill Title

## Input
What the skill needs from the user.

## Execution
Step-by-step protocol the agent follows.

## Output
What the skill produces.
```

### 3. Update the skills README

Add your skill to `plugins/cm-dev-tools/skills/README.md` in the
appropriate category.

### 4. Test the skill

Invoke it in a Copilot CLI or Claude Code session using one of the
trigger phrases from the description.

## Adding a New Plugin

### 1. Create the plugin directory

```text
plugins/<plugin-name>/
├── .claude-plugin/
│   └── plugin.json       # Required: plugin manifest
├── skills/               # Required: at least one skill
│   ├── README.md
│   └── <skill-name>/
│       └── SKILL.md
├── scripts/              # Optional: helper scripts
│   └── *.ps1
└── README.md             # Required: plugin documentation
```

### 2. Create the plugin manifest

```json
{
  "name": "my-plugin",
  "version": "1.0.0",
  "description": "What this plugin provides",
  "skills": "skills/"
}
```

### 3. Register in marketplace.json

Add an entry to `.claude-plugin/marketplace.json`:

```json
{
  "name": "my-plugin",
  "source": "./plugins/my-plugin",
  "description": "Brief description",
  "version": "1.0.0"
}
```

### 4. Update the root README

Add your plugin to the "Available Plugins" table.

## Adding a PowerShell Helper Script

Scripts go in `plugins/<plugin-name>/scripts/`. Conventions:

- Include full `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE` help
- Use `param()` blocks with `[Parameter(Mandatory)]` where appropriate
- Return structured output (not just raw text)
- Handle errors gracefully with clear messages
- Use `✅` / `❌` / `⚠️` icons for scannable output

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

## Version Bumping

When releasing a new version:

1. Update `plugins/<plugin>/plugin.json` version
2. Update `.claude-plugin/marketplace.json` version
3. Add entry to `RELEASES.md`
4. Commit, tag with `v{VERSION}`, push
