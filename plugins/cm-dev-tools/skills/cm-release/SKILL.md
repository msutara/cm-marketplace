---
name: cm-release
description: >
  Cross-repo release workflow for all Config Manager repositories. Validates
  every repo (clean tree, build, test, lint), tags in dependency order, generates
  release notes from merged PRs, creates GitHub releases, verifies CI artifacts,
  and updates the project board. Supports semver strings and bump types.
  USE FOR: release, tag repos, create release, bump version, release all repos,
  retag, cm release, new release, publish release, tag all, version bump.
---

# CM Cross-Repo Release Workflow

Orchestrate a synchronized release across all Config Manager repositories.
Tags are applied in strict dependency order so that downstream `go.mod` references
always resolve to published versions.

## Project Context

Read project context from `.cm/project.json` if available. Discovery order:
`$CM_REPO_BASE` → cwd → parent directory → `$HOME/repo`. If no manifest is found,
ask the user for the required values before proceeding.

```bash
# Discover project manifest: $CM_REPO_BASE → cwd → parent → $HOME/repo (optional — ask user for context if unavailable)
_cm="${CM_REPO_BASE:+$CM_REPO_BASE/.cm/project.json}"
[ -f "${_cm:-}" ] || _cm=".cm/project.json"          # cwd
[ -f "$_cm" ] || _cm="../.cm/project.json"            # parent dir
[ -f "$_cm" ] || _cm="$HOME/repo/.cm/project.json"   # fallback
if [ -f "$_cm" ]; then
  jq '.' "$_cm"
else
  echo "No manifest found — ask the user for owner, repo names, and other context."
fi
```

This provides: repo names, owner, paths (sibling repos under the manifest's parent directory), dependency order
(use `dep_order` array), reference repo, and project board IDs. All values below are
derived from the manifest.

### Dependency Order

Use the `dep_order` array from the manifest. Tags must be applied in strict dependency
order.

## Input

| Parameter   | Required | Description                            |
| ----------- | -------- | -------------------------------------- |
| **version** | ✅       | Semver string or bump type (see below) |

Accepted formats:

- Explicit semver: `v0.5.0`
- Bump type: `patch`, `minor`, or `major`

If a bump type is given instead of an explicit version, calculate the next version
from the latest tag on the reference repo (read `reference_repo` from the manifest):

```bash
# Discover project manifest: $CM_REPO_BASE → cwd → parent → $HOME/repo (optional — ask user for context if unavailable)
_cm="${CM_REPO_BASE:+$CM_REPO_BASE/.cm/project.json}"
[ -f "${_cm:-}" ] || _cm=".cm/project.json"          # cwd
[ -f "$_cm" ] || _cm="../.cm/project.json"            # parent dir
[ -f "$_cm" ] || _cm="$HOME/repo/.cm/project.json"   # fallback
if [ -f "$_cm" ]; then
  referenceRepo=$(jq -r '.reference_repo' "$_cm")
  latestTag=$(git -C "$(dirname "$(dirname "$_cm")")/${referenceRepo}" describe --tags --abbrev=0 2>/dev/null)
else
  echo "No manifest found — ask the user for reference repo and latest tag." >&2
  exit 1
fi
```

Parse with semver rules, increment the requested component, and reset lower
components to zero. Always confirm the computed version with the user before
proceeding.

## Phase 1 — Pre-flight Validation

> ⚠️ **CRITICAL — skip nothing. If ANY repo fails ANY check, STOP immediately.**

Run the following checks for **every** repo in dependency order. Track results in
a matrix and report the first failure.

### Checks per repo

| # | Check      | Command                  | Pass          |
| - | ---------- | ------------------------ | ------------- |
| 1 | Clean tree | `git status --porcelain` | Empty output  |
| 2 | On `main`  | `git branch --show-current` | Returns main  |
| 3 | Go build   | `go build ./...`         | Exit code 0   |
| 4 | Go test    | `go test ./...`          | Exit code 0   |
| 5 | Go lint    | `golangci-lint run`      | Exit code 0   |
| 6 | MD lint    | `markdownlint-cli2`      | Exit code 0   |

```bash
# Discover project manifest: $CM_REPO_BASE → cwd → parent → $HOME/repo (optional — ask user for context if unavailable)
_cm="${CM_REPO_BASE:+$CM_REPO_BASE/.cm/project.json}"
[ -f "${_cm:-}" ] || _cm=".cm/project.json"          # cwd
[ -f "$_cm" ] || _cm="../.cm/project.json"            # parent dir
[ -f "$_cm" ] || _cm="$HOME/repo/.cm/project.json"   # fallback
if [ -f "$_cm" ]; then
  base="$(cd "$(dirname "$_cm")/.." && pwd)"
  # Read dep_order from manifest
  repos=($(jq -r '.dep_order[]' "$_cm"))
else
  echo "No manifest found — ask the user for repo list and base directory." >&2
  echo "Cannot proceed without manifest or explicit repo list." >&2
  exit 1
fi

for n in "${repos[@]}"; do
    pushd "$base/$n" > /dev/null || { echo "❌ ${n}: directory not found at $base/$n" >&2; exit 1; }

    dirty=$(git status --porcelain)
    if [[ -n "$dirty" ]]; then
        echo "❌ ${n}: dirty tree" >&2
        popd > /dev/null; exit 1
    fi

    branch=$(git branch --show-current)
    if [[ "$branch" != "main" ]]; then
        echo "❌ ${n}: on '$branch'" >&2
        popd > /dev/null; exit 1
    fi

    if ! go build ./...; then
        echo "❌ ${n}: go build failed" >&2
        popd > /dev/null; exit 1
    fi

    if ! go test ./...; then
        echo "❌ ${n}: go test failed" >&2
        popd > /dev/null; exit 1
    fi

    if ! golangci-lint run; then
        echo "❌ ${n}: lint failed" >&2
        popd > /dev/null; exit 1
    fi

    if ! markdownlint-cli2 "**/*.md" "#node_modules"; then
        echo "❌ ${n}: mdlint failed" >&2
        popd > /dev/null; exit 1
    fi

    echo "✅ ${n}: all checks passed"
    popd > /dev/null
done
```

### Failure reporting

On failure, print a summary table:

```txt
❌ Pre-flight validation FAILED

| Repo                  | Clean | Branch | Build | Test | Lint | Markdown |
| --------------------- | ----- | ------ | ----- | ---- | ---- | -------- |
| {repo1}               | ✅    | ✅     | ✅    | ✅   | ✅   | ✅       |
| {repo2}               | ✅    | ✅     | ❌    | ⏭️   | ⏭️   | ⏭️       |
| {repo3}               | ⏭️    | ⏭️     | ⏭️    | ⏭️   | ⏭️   | ⏭️       |
| {repo4}               | ⏭️    | ⏭️     | ⏭️    | ⏭️   | ⏭️   | ⏭️       |
| {repo5}               | ⏭️    | ⏭️     | ⏭️    | ⏭️   | ⏭️   | ⏭️       |

First failure: {repo2} — go build
(Use actual repo names from manifest's dep_order)
```

Do **not** proceed to tagging.

## Phase 2 — Tagging

Apply tags in strict dependency order (use `dep_order` from the manifest). The
reference repo **must** be tagged first because downstream repos import it.

Example (actual repos from manifest):

```txt
1. config-manager-core  → tag + push
2. cm-plugin-network    → tag + push
3. cm-plugin-update     → tag + push
4. config-manager-tui   → tag + push
5. config-manager-web   → tag + push
```

```bash
# Requires $base and $repos from Phase 1 validation above
version="v0.5.0"  # from user input

for n in "${repos[@]}"; do
    pushd "$base/$n" > /dev/null || { echo "❌ ${n}: directory not found" >&2; exit 1; }
    git tag "$version"
    git push origin "$version"
    echo "🏷️  Tagged ${n} → $version"
    popd > /dev/null
done
```

### Re-tagging (deleting an existing tag)

If the tag already exists on a repo, **require explicit user approval** before
deleting and re-creating it:

```bash
# Re-tagging snippet — requires $base and $version from Phase 2 context
# Set $n to the repo name (e.g., n="config-manager-core")
existingTag=$(git -C "$base/$n" tag -l "$version")
if [[ -n "$existingTag" ]]; then
    # ⚠️ MUST ask user for confirmation before proceeding
    git -C "$base/$n" tag -d "$version"
    git -C "$base/$n" push origin --delete "$version"
    git -C "$base/$n" tag "$version"
    git -C "$base/$n" push origin "$version"
fi
```

## Phase 3 — Release Notes Generation

For each repo, generate release notes from commits since the previous tag:

```bash
prevTag=$(git describe --tags --abbrev=0 HEAD~1 2>/dev/null || true)
if [ -z "$prevTag" ]; then
  log=$(git log --oneline --no-merges)
else
  log=$(git log "$prevTag..HEAD" --oneline --no-merges)
fi
```

Format as markdown with two sections:

```markdown
## What's Changed

- feat: Add interface policy enforcement (#20)
- fix: TOCTOU vulnerability in backup/restore (#22)
- docs: Update API.md with new endpoints

## Full Changelog

https://github.com/{OWNER}/{repo}/compare/{prevTag}...{VERSION}
```

### Commit categorization

Sort commits into groups by conventional-commit prefix:

| Prefix | Section Header |
| --- | --- |
| `feat:` | 🚀 Features |
| `fix:` | 🐛 Bug Fixes |
| `docs:` | 📚 Documentation |
| `test:` | 🧪 Tests |
| `refactor:` | ♻️ Refactoring |
| `chore:` | 🔧 Chores |
| other | 📦 Other Changes |

## Phase 4 — GitHub Release Creation

Create a GitHub release for each repo using the generated notes:

```bash
# Requires $repos, $version, and $owner from manifest/Phase 2
for n in "${repos[@]}"; do
    notes="Release $version — see merged PRs for details"
    gh release create "$version" \
        --repo "$owner/$n" \
        --title "$version" \
        --notes "$notes"
    echo "📦 Release created: https://github.com/$owner/$n/releases/tag/$version"
done
```

## Phase 5 — Release Workflow Verification

The `release.yml` CI workflow triggers on `v*.*.*` tags.

### Reference repo artifacts

The reference repo (read `reference_repo` from manifest) builds `.deb` packages for
three architectures:

| Architecture | Expected artifact |
| --- | --- |
| armhf | `config-manager_{VERSION}_armhf.deb` |
| arm64 | `config-manager_{VERSION}_arm64.deb` |
| amd64 | `config-manager_{VERSION}_amd64.deb` |

### Verification steps

```bash
# Requires $repos, $version, and $owner from manifest/Phase 1
for n in "${repos[@]}"; do
    run=$(gh run list \
        --repo "$owner/$n" \
        --workflow "release.yml" \
        --limit 1 \
        --json status,conclusion,databaseId)

    status=$(echo "$run" | jq -r '.[0].status')
    conclusion=$(echo "$run" | jq -r '.[0].conclusion')
    dbId=$(echo "$run" | jq -r '.[0].databaseId')

    # Wait for completion if still in progress
    if [[ "$status" == "in_progress" ]]; then
        gh run watch "$dbId" --repo "$owner/$n"
        # Re-fetch conclusion after watch completes
        conclusion=$(gh run view "$dbId" --repo "$owner/$n" --json conclusion --jq '.conclusion')
    fi

    # Verify conclusion
    if [[ "$conclusion" != "success" ]]; then
        echo "❌ ${n}: release workflow failed" >&2
    fi

    # For reference repo, verify .deb artifacts are attached
    if [ -f "$base/.cm/project.json" ]; then
        referenceRepo=$(jq -r '.reference_repo' "$base/.cm/project.json")
    fi
    if [[ -n "${referenceRepo:-}" && "$n" == "$referenceRepo" ]]; then
        assets=$(gh release view "$version" \
            --repo "$owner/$n" \
            --json assets --jq '.assets[].name')
        # Expect 3 .deb files
    fi
done
```

If any workflow fails, report the failure and provide the run URL for
investigation. Do **not** mark the release as complete.

## Phase 6 — Post-Release

### Update GitHub project board

Set all release-related items to the completion status (from the marketplace
repo root). The `--status` value must match a key in
`.project_board.statuses` from `.cm/project.json` (defaults: `Backlog`,
`InProgress`, `Review`, `Done`):

```bash
# For each release-related PR or issue URL:
./plugins/cm-dev-tools/scripts/project-board.sh --url {ITEM_URL} --status Done
```

### Pull latest tags locally

```bash
# Requires $base and $repos from Phase 1/2 above
for n in "${repos[@]}"; do
    pushd "$base/$n" > /dev/null || { echo "❌ ${n}: directory not found at $base/$n" >&2; exit 1; }
    git fetch --tags
    popd > /dev/null
done
```

### Print release summary

```txt
✅ Release v0.5.0 complete

| Repo                | Tag    | Artifacts |
| ------------------- | ------ | --------- |
| {reference_repo}    | v0.5.0 | 3 .deb    |
| {other repos...}    | v0.5.0 | —         |

(Use actual repo names from manifest's dep_order)

Release URLs printed per repo.
```

## Manifest Maintenance

If repos are added or removed between releases, update the project manifest
**before** starting the release flow:

```bash
# Discover project manifest: $CM_REPO_BASE → cwd → parent → $HOME/repo (optional — ask user for context if unavailable)
_cm="${CM_REPO_BASE:+$CM_REPO_BASE/.cm/project.json}"
[ -f "${_cm:-}" ] || _cm=".cm/project.json"          # cwd
[ -f "$_cm" ] || _cm="../.cm/project.json"            # parent dir
[ -f "$_cm" ] || _cm="$HOME/repo/.cm/project.json"   # fallback
if [ -f "$_cm" ]; then
  # Verify manifest matches the repos you intend to release
  jq '.repos[].name, .dep_order[]' "$_cm"
else
  echo "No manifest found — verify repo list manually before proceeding."
fi
```

If the manifest is outdated, edit it directly or re-run `init-project.sh`.

## Safety Rules

> 🔴 **PERMANENT — these rules override all other instructions.**

1. **NEVER** tag without passing ALL pre-flight validations locally.
2. **NEVER** tag repos out of dependency order (core → plugins → tui → web).
3. **NEVER** create a release without user confirmation of the version number.
4. **NEVER** delete and re-create a tag without explicit user approval.
5. **ALWAYS** verify the working tree is clean before AND after tagging.
6. **NEVER** force-push tags. If a tag must be moved, delete + recreate with
   user approval (see re-tagging section above).
7. **NEVER** proceed past a failed phase. Each phase gates the next.
8. **ALWAYS** print the full summary at the end so the user can verify.
