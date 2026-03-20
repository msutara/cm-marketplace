---
name: cm-release
description: >
  Cross-repo release workflow for all 5 Config Manager repositories. Validates
  every repo (clean tree, build, test, lint), tags in dependency order, generates
  release notes from merged PRs, creates GitHub releases, verifies CI artifacts,
  and updates the project board. Supports semver strings and bump types.
triggers:
  - release
  - tag repos
  - create release
  - bump version
  - release all repos
  - retag
  - cm release
  - new release
  - publish release
  - tag all
  - version bump
repos:
  - name: config-manager-core
    path: C:\Users\marius\repo\config-manager-core
    owner: msutara
    order: 1
    role: central service
  - name: cm-plugin-network
    path: C:\Users\marius\repo\cm-plugin-network
    owner: msutara
    order: 2
    role: network config plugin
  - name: cm-plugin-update
    path: C:\Users\marius\repo\cm-plugin-update
    owner: msutara
    order: 3
    role: OS update plugin
  - name: config-manager-tui
    path: C:\Users\marius\repo\config-manager-tui
    owner: msutara
    order: 4
    role: Bubble Tea TUI
  - name: config-manager-web
    path: C:\Users\marius\repo\config-manager-web
    owner: msutara
    order: 5
    role: htmx web UI
github_project:
  id: PVT_kwHOAgHix84BPSxN
  status_field_id: PVTSSF_lAHOAgHix84BPSxNzg9vkrk
  done_option: "98236657"
dependency_order:
  - config-manager-core
  - cm-plugin-network
  - cm-plugin-update
  - config-manager-tui
  - config-manager-web
---

# CM Cross-Repo Release Workflow

Orchestrate a synchronized release across all 5 Config Manager repositories.
Tags are applied in strict dependency order so that downstream `go.mod` references
always resolve to published versions.

## Input

| Parameter   | Required | Description                            |
| ----------- | -------- | -------------------------------------- |
| **version** | ✅       | Semver string or bump type (see below) |

Accepted formats:

- Explicit semver: `v0.5.0`
- Bump type: `patch`, `minor`, or `major`

If a bump type is given instead of an explicit version, calculate the next version
from the latest git tag across all repos:

```bash
latestTag=$(git -C "$repoPath" describe --tags --abbrev=0 2>/dev/null)
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
| 2 | On `main`  | `git branch --show`      | Returns main  |
| 3 | Go build   | `go build ./...`         | Exit code 0   |
| 4 | Go test    | `go test ./...`          | Exit code 0   |
| 5 | Go lint    | `golangci-lint run`      | Exit code 0   |
| 6 | MD lint    | `markdownlint-cli2`      | Exit code 0   |

```bash
base="$HOME/repo"
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
prevTag=$(git describe --tags --abbrev=0 HEAD~1 2>/dev/null)
log=$(git log "$prevTag..HEAD" --oneline --no-merges)
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
for n in "${repos[@]}"; do
    notes=# assembled from Phase 3
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
for n in "${repos[@]}"; do
    # Check latest release workflow run
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
# Query items linked to the release milestone/version
# Update status field to Done
gh api graphql -f query='
  mutation {
    updateProjectV2ItemFieldValue(
      input: {
        projectId: "PVT_kwHOAgHix84BPSxN"
        itemId: "$ITEM_ID"
        fieldId: "PVTSSF_lAHOAgHix84BPSxNzg9vkrk"
        value: { singleSelectOptionId: "98236657" }
      }
    ) { projectV2Item { id } }
  }'
```

### Pull latest tags locally

```bash
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
