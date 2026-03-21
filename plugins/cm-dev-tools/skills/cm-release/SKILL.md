---
name: cm-release
description: >
  Cross-repo release workflow for all 5 Config Manager repositories. Validates
  every repo (clean tree, build, test, lint), tags in dependency order, generates
  release notes from merged PRs, creates GitHub releases, verifies CI artifacts,
  and updates the project board. Supports semver strings and bump types.
  USE FOR: release, tag repos, create release, bump version, release all repos,
  retag, cm release, new release, publish release, tag all, version bump.
---

# CM Cross-Repo Release Workflow

Orchestrate a synchronized release across all 5 Config Manager repositories.
Tags are applied in strict dependency order so that downstream `go.mod` references
always resolve to published versions.

## Project Context

### Repos (in dependency order)

| Order | Repo | Path | Owner | Role |
| --- | --- | --- | --- | --- |
| 1 | config-manager-core | `$CM_REPO_BASE/config-manager-core` | msutara | central service |
| 2 | cm-plugin-network | `$CM_REPO_BASE/cm-plugin-network` | msutara | network config plugin |
| 3 | cm-plugin-update | `$CM_REPO_BASE/cm-plugin-update` | msutara | OS update plugin |
| 4 | config-manager-tui | `$CM_REPO_BASE/config-manager-tui` | msutara | Bubble Tea TUI |
| 5 | config-manager-web | `$CM_REPO_BASE/config-manager-web` | msutara | htmx web UI |

### Dependency Order

Tags must be applied in this order: config-manager-core → cm-plugin-network → cm-plugin-update → config-manager-tui → config-manager-web.

### GitHub Project

| Key | Value |
| --- | --- |
| Project ID | `PVT_kwHOAgHix84BPSxN` |
| Status field ID | `PVTSSF_lAHOAgHix84BPSxNzg9vkrk` |
| Done option | `98236657` |

## Input

| Parameter   | Required | Description                            |
| ----------- | -------- | -------------------------------------- |
| **version** | ✅       | Semver string or bump type (see below) |

Accepted formats:

- Explicit semver: `v0.5.0`
- Bump type: `patch`, `minor`, or `major`

If a bump type is given instead of an explicit version, calculate the next version
from the latest tag on `config-manager-core` (the root dependency):

```bash
latestTag=$(git -C "${CM_REPO_BASE:-$HOME/repo}/config-manager-core" describe --tags --abbrev=0 2>/dev/null)
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
base="${CM_REPO_BASE:-$HOME/repo}"
repos=(
    "config-manager-core"
    "cm-plugin-network"
    "cm-plugin-update"
    "config-manager-tui"
    "config-manager-web"
)

for n in "${repos[@]}"; do
    pushd "$base/$n" > /dev/null

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
| config-manager-core   | ✅    | ✅     | ✅    | ✅   | ✅   | ✅       |
| cm-plugin-network     | ✅    | ✅     | ❌    | ⏭️   | ⏭️   | ⏭️       |
| cm-plugin-update      | ⏭️    | ⏭️     | ⏭️    | ⏭️   | ⏭️   | ⏭️       |
| config-manager-tui    | ⏭️    | ⏭️     | ⏭️    | ⏭️   | ⏭️   | ⏭️       |
| config-manager-web    | ⏭️    | ⏭️     | ⏭️    | ⏭️   | ⏭️   | ⏭️       |

First failure: cm-plugin-network — go build
```

Do **not** proceed to tagging.

## Phase 2 — Tagging

Apply tags in strict dependency order. Core **must** be tagged first because
plugins import it, and tui/web import plugins + core.

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
    pushd "$base/$n" > /dev/null
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

https://github.com/msutara/{repo}/compare/{prevTag}...{VERSION}
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
# Requires $repos and $version from Phase 2 above
for n in "${repos[@]}"; do
    notes="Release $version — see merged PRs for details"
    gh release create "$version" \
        --repo "msutara/$n" \
        --title "$version" \
        --notes "$notes"
    echo "📦 Release created: https://github.com/msutara/$n/releases/tag/$version"
done
```

## Phase 5 — Release Workflow Verification

The `release.yml` CI workflow triggers on `v*.*.*` tags.

### config-manager-core artifacts

The core repo builds `.deb` packages for three architectures:

| Architecture | Expected artifact |
| --- | --- |
| armhf | `config-manager_{VERSION}_armhf.deb` |
| arm64 | `config-manager_{VERSION}_arm64.deb` |
| amd64 | `config-manager_{VERSION}_amd64.deb` |

### Verification steps

```bash
# Requires $repos and $version from Phase 1 validation above
for n in "${repos[@]}"; do
    run=$(gh run list \
        --repo "msutara/$n" \
        --workflow "release.yml" \
        --limit 1 \
        --json status,conclusion,databaseId)

    status=$(echo "$run" | jq -r '.[0].status')
    conclusion=$(echo "$run" | jq -r '.[0].conclusion')
    dbId=$(echo "$run" | jq -r '.[0].databaseId')

    # Wait for completion if still in progress
    if [[ "$status" == "in_progress" ]]; then
        gh run watch "$dbId" --repo "msutara/$n"
    fi

    # Verify conclusion
    if [[ "$conclusion" != "success" ]]; then
        echo "❌ ${n}: release workflow failed" >&2
    fi

    # For core repo, verify .deb artifacts are attached
    if [[ "$n" == "config-manager-core" ]]; then
        assets=$(gh release view "$version" \
            --repo "msutara/$n" \
            --json assets --jq '.assets[].name')
        # Expect 3 .deb files
    fi
done
```

If any workflow fails, report the failure and provide the run URL for
investigation. Do **not** mark the release as complete.

## Phase 6 — Post-Release

### Update GitHub project board

Set all release-related items to **Done**:

```bash
# Replace $ITEM_ID with the actual project item ID for each release item
ITEM_ID="PVTI_..."  # from gh project item-list or item-add
gh api graphql -f query="
  mutation {
    updateProjectV2ItemFieldValue(
      input: {
        projectId: \"PVT_kwHOAgHix84BPSxN\"
        itemId: \"$ITEM_ID\"
        fieldId: \"PVTSSF_lAHOAgHix84BPSxNzg9vkrk\"
        value: { singleSelectOptionId: \"98236657\" }
      }
    ) { projectV2Item { id } }
  }"
```

### Pull latest tags locally

```bash
# Requires $base and $repos from Phase 1/2 above
for n in "${repos[@]}"; do
    pushd "$base/$n" > /dev/null
    git fetch --tags
    popd > /dev/null
done
```

### Print release summary

```txt
✅ Release v0.5.0 complete

| Repo                | Tag    | Artifacts |
| ------------------- | ------ | --------- |
| config-manager-core | v0.5.0 | 3 .deb    |
| cm-plugin-network   | v0.5.0 | —         |
| cm-plugin-update    | v0.5.0 | —         |
| config-manager-tui  | v0.5.0 | —         |
| config-manager-web  | v0.5.0 | —         |

Release URLs printed per repo.
```

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
