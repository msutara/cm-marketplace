---
name: cm-docs-sync
description: >
  Documentation consistency auditing across all CM repos. Scans configuration
  files for drift, validates copilot-instructions.md accuracy, cross-references
  specs with code, checks README freshness, and runs markdownlint. Generates a
  unified report and optionally auto-fixes mechanical divergences.
  USE FOR: sync docs, docs audit, check documentation, update docs,
  docs consistency, audit docs, documentation check, verify docs, docs parity.
---

# CM Documentation Consistency Audit

Audit and enforce documentation parity across all CM repositories.

## Repositories

Read project context from `.cm/project.json` if available. Discovery order:
`$CM_REPO_BASE` → parent directory → `$HOME/repo`. If no manifest is found,
ask the user for the required values before proceeding.

```bash
# Discover project manifest (recommended — ask user for context if unavailable)
_cm="${CM_REPO_BASE:+$CM_REPO_BASE/.cm/project.json}"
[ -f "${_cm:-}" ] || _cm=".cm/project.json"
[ -f "$_cm" ] || _cm="../.cm/project.json"
[ -f "$_cm" ] || _cm="$HOME/repo/.cm/project.json"
if [ -f "$_cm" ]; then
  jq '.repos[] | "\(.name) → \(.role)"' "$_cm"
else
  echo "No manifest found — ask the user for owner, repo names, and other context."
fi
```

The **reference repo** (use `reference_repo` from manifest) is the source of truth
for identical configuration files.

## Step 1 — Scan Configuration Files

Compare files that MUST be identical (or structurally identical) across all repos.

| File | Must Match | Notes |
| --- | --- | --- |
| `.markdownlint.json` | Byte-identical | Full 28-rule config (see `config-manager-core/.markdownlint.json` as reference) |
| `.golangci.yml` | Structurally identical | v2 format; repo-specific linter exclusions are acceptable |
| `.github/dependabot.yml` | Structurally identical | gomod + github-actions, weekly schedule |
| `.github/workflows/ci.yml` | Pattern-matching | Same actions versions, same steps; repo-specific test commands expected |
| `.github/PULL_REQUEST_TEMPLATE.md` | Identical | Standard PR template |

### Procedure

For each file listed above:

1. Read the file from every repo. Record which repos are missing it.
2. Diff pairwise against the reference repo (read `reference_repo` from manifest).
3. For **byte-identical** files — any difference is a finding.
4. For **structurally identical** files — parse YAML, compare keys and values, allow documented repo-specific overrides.
5. For **pattern-matching** files — verify action versions and step names match; flag divergent steps.
6. Collect findings into the report (Step 6).

## Step 2 — Validate copilot-instructions.md

Each repo has `.github/copilot-instructions.md` with repo-specific context.

For every repo, verify:

- References the correct repo name and Go import path.
- Architecture section matches the actual directory structure (`ls -R` or `tree` top-level dirs).
- Plugin interface references (function signatures, interface names) are up-to-date with code.
- Conventions section is consistent with the equivalent section in other repos.
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
cd "{repo_path}" || { echo "Failed to cd into {repo_path}"; exit 1; }
markdownlint-cli2 "**/*.md" "#node_modules"
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

- ✅ {reference_repo}: matches reference
- ✅ {repo2}: matches reference
- ⚠️ {repo3}: MISSING (file not found)
- ✅ {repo4}: matches reference
- ✅ {repo5}: matches reference

(Use actual repo names from manifest)

### .golangci.yml

- ✅ All repos: structurally identical (v2 format)
- ℹ️ Web repo may have additional staticcheck exclusion for ST1005 (capitalized errors in HTTP handlers)

(Use actual repo names from manifest)

### .github/dependabot.yml

- ✅ All repos: structurally identical

(Use actual repo names from manifest)

### .github/workflows/ci.yml

- ✅ All repos: same actions versions (actions/checkout@v6, actions/setup-go@v5)
- ℹ️ Web repo may use additional `npm ci` step (expected)

(Use actual repo names from manifest)

### .github/PULL_REQUEST_TEMPLATE.md

- ✅ All repos: identical

(Use actual repo names from manifest)

## Spec Accuracy

### {reference_repo}

- ✅ 12/12 API endpoints match code
- ⚠️ SPEC.md documents `GET /api/v1/jobs/{id}/runs` but code has `GET /api/v1/jobs/{id}/runs/latest`

(Use actual repo names from manifest)

## copilot-instructions.md

- ✅ {reference_repo}: accurate
- ⚠️ {repo2}: references `internal/plugin/` but interface moved to `plugin/` (stale)

(Use actual repo names from manifest)

## README.md

- ⚠️ {reference_repo}: installation says v0.3.0 but latest tag is v0.4.3
- ✅ Other repos: up-to-date

(Use actual repo names from manifest)

## Markdownlint

- ✅ {reference_repo}: 0 violations
- ⚠️ {repo2}: 2 violations in SPEC.md (MD032: blank line around list)

(Use actual repo names from manifest)

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

- Copy the reference file from the reference repo (read `reference_repo` from manifest) to repos where it is missing or diverged.
- Fix markdownlint violations (trailing whitespace, missing blank lines, etc.).
- Update version references in README installation instructions.

### Semantic Fixes (flag for manual review)

- Spec/code mismatches — **do NOT auto-fix**. Flag them and let the user decide whether the spec or the code is correct.
- Stale copilot-instructions references — suggest the fix but let the user confirm.

## Notes

- Some divergence is expected and acceptable: repo-specific `copilot-instructions.md` content, repo-specific linter exclusions in `.golangci.yml`, repo-specific test commands in CI.
- Spec/code mismatches are the highest-priority findings — they mislead both humans and AI agents.
- Run this skill **before every release** to catch documentation drift early.
