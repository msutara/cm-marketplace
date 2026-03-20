---
name: cm-docs-sync
description: >
  Documentation consistency auditing across all 5 CM repos. Scans configuration
  files for drift, validates copilot-instructions.md accuracy, cross-references
  specs with code, checks README freshness, and runs markdownlint. Generates a
  unified report and optionally auto-fixes mechanical divergences.
triggers:
  - "sync docs"
  - "docs audit"
  - "check documentation"
  - "update docs"
  - "docs consistency"
  - "audit docs"
  - "documentation check"
  - "verify docs"
  - "docs parity"
---

# CM Documentation Consistency Audit

Audit and enforce documentation parity across all 5 CM repositories.

## Repositories

| # | Repo | Path |
| --- | --- | --- |
| 1 | `config-manager-core` | `C:\Users\marius\repo\config-manager-core` |
| 2 | `cm-plugin-network` | `C:\Users\marius\repo\cm-plugin-network` |
| 3 | `cm-plugin-update` | `C:\Users\marius\repo\cm-plugin-update` |
| 4 | `config-manager-tui` | `C:\Users\marius\repo\config-manager-tui` |
| 5 | `config-manager-web` | `C:\Users\marius\repo\config-manager-web` |

The **reference repo** for identical files is `config-manager-core`.

## Step 1 — Scan Configuration Files

Compare files that MUST be identical (or structurally identical) across all 5 repos.

| File | Must Match | Notes |
| --- | --- | --- |
| `.markdownlint.json` | Byte-identical | `{"default":true,"MD013":false,"MD033":{"allowed_elements":["br"]},"MD024":{"siblings_only":true}}` |
| `.golangci.yml` | Structurally identical | v2 format; repo-specific linter exclusions are acceptable |
| `dependabot.yml` | Structurally identical | gomod + github-actions, weekly schedule |
| `.github/workflows/ci.yml` | Pattern-matching | Same actions versions, same steps; repo-specific test commands expected |
| `.github/PULL_REQUEST_TEMPLATE.md` | Identical | Standard PR template |

### Procedure

For each file listed above:

1. Read the file from every repo. Record which repos are missing it.
2. Diff pairwise against the reference (`config-manager-core`).
3. For **byte-identical** files — any difference is a finding.
4. For **structurally identical** files — parse YAML, compare keys and values, allow documented repo-specific overrides.
5. For **pattern-matching** files — verify action versions and step names match; flag divergent steps.
6. Collect findings into the report (Step 6).

## Step 2 — Validate copilot-instructions.md

Each repo has `.github/copilot-instructions.md` with repo-specific context.

For every repo, verify:

- References the correct repo name and Go import path.
- Architecture section matches the actual directory structure (`ls -Recurse` top-level dirs).
- Plugin interface references (function signatures, interface names) are up-to-date with code.
- Conventions section is consistent with the equivalent section in the other 4 repos.
- Every file path mentioned in the document actually exists on disk.

Flag stale references (e.g., `internal/plugin/` when the interface moved to `plugin/`).

## Step 3 — Cross-Reference specs/SPEC.md with Code

For each repo that has a `specs/SPEC.md`:

1. **Parse API endpoints** — extract every `METHOD /path` from the spec.
2. **Parse route registrations** — find `router.GET`, `router.POST`, etc. in `routes.go` (or equivalent).
3. **Flag mismatches:**
   - Endpoints in spec but not in code (documented but unimplemented).
   - Endpoints in code but not in spec (implemented but undocumented).
4. **Check status codes** — verify documented response codes match actual `c.JSON(status, ...)` calls.
5. **Check JSON field names** — compare field names in spec examples with Go struct tags (`json:"..."`).

Spec/code mismatches are **HIGH priority** — they mislead both humans and AI agents.

## Step 4 — Verify README.md Consistency

For each repo's `README.md`:

- Installation instructions reference the **latest release version** (compare with `git describe --tags --abbrev=0`).
- Feature lists are up-to-date with actual exported functionality.
- Configuration examples match the actual config struct fields and defaults.
- CLI flags and environment variables match what the code registers.
- Badge URLs are correct and resolve (CI status, Go Report Card, etc.).

## Step 5 — Run markdownlint

For each repo, execute:

```bash
cd {repo_path} && markdownlint-cli2 "**/*.md" "#node_modules"
```

Collect violations per repo and include them in the report.

## Step 6 — Generate Report

Produce a single markdown report with sections for every check. Use status icons to make the report scannable.

### Report Template

````markdown
# Documentation Consistency Report

Generated: {timestamp}

## Configuration Files

### .markdownlint.json

- ✅ config-manager-core: matches reference
- ✅ cm-plugin-network: matches reference
- ⚠️ cm-plugin-update: MISSING (file not found)
- ✅ config-manager-tui: matches reference
- ✅ config-manager-web: matches reference

### .golangci.yml

- ✅ All 5 repos: structurally identical (v2 format)
- ℹ️ Web has additional staticcheck exclusion for ST1005 (capitalized errors in HTTP handlers)

### dependabot.yml

- ✅ All 5 repos: structurally identical

### .github/workflows/ci.yml

- ✅ All 5 repos: same actions versions (actions/checkout@v4, actions/setup-go@v5)
- ℹ️ config-manager-web uses additional `npm ci` step (expected)

### .github/PULL_REQUEST_TEMPLATE.md

- ✅ All 5 repos: identical

## Spec Accuracy

### config-manager-core

- ✅ 12/12 API endpoints match code
- ⚠️ SPEC.md documents `GET /api/v1/jobs/{id}/runs` but code has `GET /api/v1/jobs/{id}/runs/latest`

### cm-plugin-network

- ✅ 4/4 API endpoints match code

### cm-plugin-update

- ✅ 6/6 API endpoints match code

### config-manager-tui

- ℹ️ No API spec (TUI only)

### config-manager-web

- ⚠️ 2 endpoints in code but not in spec

## copilot-instructions.md

- ✅ config-manager-core: accurate
- ✅ cm-plugin-network: accurate
- ⚠️ cm-plugin-update: references `internal/plugin/` but interface moved to `plugin/` (stale)
- ✅ config-manager-tui: accurate
- ✅ config-manager-web: accurate

## README.md

- ⚠️ config-manager-core: installation says v0.3.0 but latest tag is v0.4.3
- ✅ cm-plugin-network: up-to-date
- ✅ cm-plugin-update: up-to-date
- ✅ config-manager-tui: up-to-date
- ✅ config-manager-web: up-to-date

## Markdownlint

- ✅ config-manager-core: 0 violations
- ⚠️ cm-plugin-network: 2 violations in SPEC.md (MD032: blank line around list)
- ✅ cm-plugin-update: 0 violations
- ✅ config-manager-tui: 0 violations
- ✅ config-manager-web: 0 violations

## Summary

| Category | ✅ Pass | ⚠️ Warn | ❌ Fail |
| --- | --- | --- | --- |
| Config files | 4 | 1 | 0 |
| Spec accuracy | 3 | 2 | 0 |
| copilot-instructions | 4 | 1 | 0 |
| README | 4 | 1 | 0 |
| Markdownlint | 4 | 1 | 0 |
````

## Step 7 — Auto-Fix (Optional, With User Approval)

**Always ask the user before making any changes.**

### Mechanical Fixes (safe to auto-apply)

- Copy the reference file from `config-manager-core` to repos where it is missing or diverged.
- Fix markdownlint violations (trailing whitespace, missing blank lines, etc.).
- Update version references in README installation instructions.

### Semantic Fixes (flag for manual review)

- Spec/code mismatches — **do NOT auto-fix**. Flag them and let the user decide whether the spec or the code is correct.
- Stale copilot-instructions references — suggest the fix but let the user confirm.

## Notes

- Some divergence is expected and acceptable: repo-specific `copilot-instructions.md` content, repo-specific linter exclusions in `.golangci.yml`, repo-specific test commands in CI.
- Spec/code mismatches are the highest-priority findings — they mislead both humans and AI agents.
- Run this skill **before every release** to catch documentation drift early.
