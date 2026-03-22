# CM Marketplace

A plugin marketplace for the Config Manager project. Provides workflow skills and bash helper scripts loadable by both Claude Code and GitHub Copilot CLI.

## Repository Structure

- **`.claude-plugin/marketplace.json`** — Marketplace manifest (both platforms read this)
- **`plugins/<name>/`** — Each plugin directory with its own `.claude-plugin/plugin.json`, README, skills, and scripts

## Plugin Patterns

The marketplace currently supports plugins with skills, agents, and bash helper scripts:

- **Skills** — `SKILL.md` files with YAML frontmatter and execution protocols
- **Agents** — `.agent.md` files with embedded project knowledge
- **Scripts** — Bash `.sh` helper scripts invoked by skills

## Before Committing

1. **Lint all** — `npm run lint:all` (markdownlint + Biome JS, must pass)
2. **Fix automatically** — `npm run lint:fix` for auto-fixable issues
3. **Verify JSON** — ensure all `.json` files are valid (marketplace.json, plugin.json)
4. **Cross-check names** — plugin name in `plugin.json` must match the entry in `marketplace.json`
5. **Check SKILL.md** — every skill has YAML frontmatter with `name` and `description` fields

## Lint Scripts

| Script | What it checks |
| --- | --- |
| `npm run lint` | Markdown files (markdownlint) |
| `npm run lint:js` | JavaScript/TypeScript files (Biome) |
| `npm run lint:fix` | Auto-fix markdown issues |
| `npm run lint:js:fix` | Auto-fix JS/TS issues (Biome) |
| `npm run lint:all` | Runs both `lint` + `lint:js` |

## Markdown Standards

Config: `.markdownlint.json` — key rules:

- ATX-style headings (`#`, `##`) with blank lines before and after
- Dash (`-`) for unordered lists
- Fenced code blocks with language identifiers
- No trailing whitespace, no consecutive blank lines
- Asterisk style for bold/italic

## Adding a Plugin

See `CONTRIBUTING.md` for the full guide. Summary:

1. Create `plugins/<name>/` with `.claude-plugin/plugin.json`, `README.md`, and `skills/`
2. Add the plugin entry to `.claude-plugin/marketplace.json`
3. Add a row to the Available Plugins table in root `README.md`
4. Run `npm run lint:all` to verify

## Do Not

- Commit secrets, credentials, or connection strings
- Skip linting before pushing (`npm run lint:all`)
- Do not use non-`.sh` extensions for scripts — all helper scripts are bash
- Add Node.js runtime dependencies — marketplace tooling is lint-only; plugins use bash scripts
