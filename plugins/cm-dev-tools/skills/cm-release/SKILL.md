---
name: cm-release
description: >
  Cross-repo release workflow for all Config Manager repositories. Validates
  every repo (clean tree, build, test, lint), determines release scope, tags in
  multi-wave dependency order with go.mod sync between waves, generates rich
  release notes with repo context and categorized changelogs, creates GitHub
  releases, verifies CI artifacts, and updates the project board. Supports
  semver strings and bump types. Includes rollback/recovery for partial releases.
  USE FOR: release, tag repos, create release, bump version, release all repos,
  retag, cm release, new release, publish release, tag all, version bump.
---

# CM Cross-Repo Release Workflow

Orchestrate a synchronized release across all Config Manager repositories.
Tags are applied in **multi-wave dependency order** — leaf modules first, then
modules that import them — with `go.mod` sync between waves so that every
repo's CI build resolves correct dependency versions.

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

This provides: repo names, owner, paths (sibling repos under the manifest's parent
directory), dependency order (use `dep_order` array), reference repo, and project
board IDs. All values below are derived from the manifest.

### Tagging Order (Multi-Wave)

Tags must be applied in **reverse import order** — leaf modules first, then
modules that import them. This is required because:

- Plugins import core (for the `plugin.Plugin` interface)
- Core imports plugins (to register them into the binary)

This circular dependency means you **cannot** tag everything in one linear pass.

| Wave | Repos | Phase | Why |
| --- | --- | --- | --- |
| 1 | Plugins (leaf modules) | 3 | Reference the current/previous core tag |
| — | go.mod sync in core | 4 | Core picks up new plugin tags |
| 2 | Core | 5 | Must `go get` new plugin tags first |
| — | go.mod sync in UI | 5.5 | UI picks up new core + plugin tags |
| 3 | UI repos (tui, web) | 6 | Import core + plugins |

Between waves, run `go.mod` sync (Phase 4 for core, Phase 5.5 for UI) so
importing repos pick up the freshly-tagged versions.

## Input

| Parameter | Required | Description |
| --- | --- | --- |
| **version** | ✅ | Semver string or bump type (see below) |

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

## Phase 0 — Authentication Check

Before any operations that interact with GitHub, verify the correct account:

```bash
gh auth status
```

In multi-account setups (e.g., EMU work account + personal account), ensure the
personal account (`msutara` or whichever owns the CM repos) is active. If not:

```bash
gh auth switch --user msutara
```

Do **not** proceed until `gh auth status` shows the correct account.

## Phase 1 — Pre-flight Validation

> ⚠️ **CRITICAL — skip nothing. If ANY repo fails ANY check, STOP immediately.**

Run the following checks for **every** repo in dependency order. Track results in
a matrix and report the first failure.

### Checks per repo

| # | Check | Command | Pass |
| --- | --- | --- | --- |
| 1 | Clean tree | `git status --porcelain` | Empty output |
| 2 | On `main` | `git branch --show-current` | Returns main |
| 3 | Go build | `go build ./...` | Exit code 0 |
| 4 | Go test | `go test ./...` | Exit code 0 |
| 5 | Go lint | `golangci-lint run` | Exit code 0 |
| 6 | MD lint | `markdownlint-cli2` | Exit code 0 |

```bash
# Discover project manifest: $CM_REPO_BASE → cwd → parent → $HOME/repo (optional — ask user for context if unavailable)
_cm="${CM_REPO_BASE:+$CM_REPO_BASE/.cm/project.json}"
[ -f "${_cm:-}" ] || _cm=".cm/project.json"          # cwd
[ -f "$_cm" ] || _cm="../.cm/project.json"            # parent dir
[ -f "$_cm" ] || _cm="$HOME/repo/.cm/project.json"   # fallback
if [ -f "$_cm" ]; then
  base="$(cd "$(dirname "$_cm")/.." && pwd)"
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

Do **not** proceed to Phase 2.

## Phase 2 — Release Scope

Not every repo needs a new tag on every release. Only repos with meaningful
changes should be tagged. Compare commits since each repo's last tag:

```bash
for n in "${repos[@]}"; do
    pushd "$base/$n" > /dev/null
    lastTag=$(git describe --tags --abbrev=0 2>/dev/null || echo "none")
    if [[ "$lastTag" == "none" ]]; then
        changes="(first release)"
    else
        changes=$(git log "$lastTag..HEAD" --oneline --no-merges)
    fi
    echo "--- $n (last: $lastTag) ---"
    echo "$changes"
    popd > /dev/null
done
```

Categorize each repo:

- If there are `feat:` or `fix:` commits → **include** in release
- If there are only `chore:`, `ci:`, `docs:` commits → **skip** (or ask user)
- If the repo would skip a version number (e.g., v0.4.3 → v0.4.5) → flag for
  user decision

Print a scope table and **confirm with the user** before proceeding:

```txt
Release Scope for v0.5.0

| Repo              | Last Tag | Changes            | Include? |
| ----------------- | -------- | ------------------ | -------- |
| cm-plugin-network | v0.4.4   | 1 feat, 1 fix      | ✅       |
| cm-plugin-update  | v0.4.4   | 1 feat              | ✅       |
| config-manager-core | v0.4.4 | 2 feat, go.mod bump | ✅       |
| config-manager-tui | v0.4.3  | 3 chores only       | ❌ skip  |
| config-manager-web | v0.4.4  | 1 docs only         | ❌ skip  |

Proceed with 3 repos? [y/N]
```

Only included repos participate in Phases 3–9. Skipped repos keep their
current tag.

> ⚠️ If **no repos** are included (all chore-only), abort the release. A
> release with zero tagged repos is not meaningful. Tell the user and stop.

### Derive wave arrays

Split the included repos into waves based on the manifest's `dep_order` and
each repo's role. Repos that import other project modules are "importers";
repos that don't are "leaves." Core sits between plugins and UI:

```bash
# After Phase 2 scope confirmation, build the wave arrays.
# Populate included_repos from user-approved scope (repos marked ✅).
# This array must be set before proceeding — fail if empty.
included_repos=()  # ← populate from Phase 2 scope decisions
# Example: included_repos=("cm-plugin-network" "cm-plugin-update" "config-manager-core")

if [ ${#included_repos[@]} -eq 0 ]; then
    echo "❌ No repos included in release scope. Aborting." >&2
    exit 1
fi

# Read roles from manifest: plugins are leaves, core is mid, UI is last.
leaf_repos=()
core_repos=()
ui_repos=()

for n in "${included_repos[@]}"; do
    role=$(jq -r --arg name "$n" '.repos[] | select(.name == $name) | .role' "$_cm")
    case "$role" in
        plugin|library) leaf_repos+=("$n") ;;
        core)           core_repos+=("$n") ;;
        tui|web|ui)     ui_repos+=("$n") ;;
        *)              leaf_repos+=("$n") ;;  # default to leaf
    esac
done

echo "Wave 1 (leaves):  ${leaf_repos[*]}"
echo "Wave 2 (core):    ${core_repos[*]}"
echo "Wave 3 (UI):      ${ui_repos[*]}"
```

## Phase 3 — Tag Wave 1: Leaf Modules

Tag **plugins and library repos** first — these are leaf modules that reference
the current (already-published) core version.

### Tag annotations

Use annotated tags (`git tag -a`) with a rich multi-line message:

```bash
# For each leaf repo included in scope
for n in "${leaf_repos[@]}"; do
    pushd "$base/$n" > /dev/null || { echo "❌ ${n}: directory not found" >&2; exit 1; }

    # Generate annotation content
    prevTag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    if [ -n "$prevTag" ]; then
        changelog=$(git log "$prevTag..HEAD" --oneline --no-merges)
    else
        changelog=$(git log --oneline --no-merges)
    fi

    annotation="Release $version — $(echo "$changelog" | head -1)

Changes:
$changelog

Full changelog: https://github.com/$owner/$n/compare/${prevTag:-initial}...$version"

    git tag -a "$version" -m "$annotation" || { echo "❌ ${n}: git tag failed" >&2; exit 1; }
    git push origin "$version" || { echo "❌ ${n}: git push tag failed" >&2; exit 1; }
    echo "🏷️  Tagged ${n} → $version"
    popd > /dev/null
done
```

### Go module proxy wait

After pushing plugin tags, the Go module proxy needs time to index them.
Before proceeding to Phase 4, verify the tags are available:

```bash
for n in "${leaf_repos[@]}"; do
    module="github.com/$owner/$n"
    indexed=false
    for attempt in 1 2 3 4 5; do
        if GOWORK=off go list -m "$module@$version" 2>/dev/null; then
            echo "✅ $module@$version available on proxy"
            indexed=true
            break
        fi
        echo "⏳ Waiting for proxy to index $module@$version (attempt $attempt/5)..."
        sleep 10
    done
    if [ "$indexed" = false ]; then
        echo "❌ $module@$version NOT available on proxy after 5 attempts." >&2
        echo "   Check: https://proxy.golang.org/$module/@v/$version.info" >&2
        echo "   STOP — do not proceed to Phase 4 until all modules are indexed." >&2
        exit 1
    fi
done
```

## Phase 4 — go.mod Sync (Core)

> ⚠️ **CRITICAL — this phase MUST happen between wave 1 and wave 2.**

After tagging leaf modules, update `go.mod` in core repos that import them.
The go.mod bump **MUST go through a PR** — never push directly to main.

```bash
for n in "${core_repos[@]}"; do
    pushd "$base/$n" > /dev/null || { echo "❌ ${n}: directory not found" >&2; exit 1; }

    # Create release branch
    git checkout -b "release/$version"

    # Bump all freshly-tagged dependencies
    for leaf in "${leaf_repos[@]}"; do
        module="github.com/$owner/$leaf"
        GOWORK=off go get "$module@$version"
    done

    go mod tidy

    # Verify build + test WITHOUT go.work (simulates CI)
    GOWORK=off go build ./...
    GOWORK=off go test ./... -count=1

    # Commit and PR
    git add go.mod go.sum
    git commit -m "release: bump plugin dependencies to $version"
    git push origin "release/$version"

    gh pr create \
        --title "release: bump deps to $version" \
        --body "Automated go.mod bump for release $version." \
        --base main

    echo "⏳ Waiting for CI on $n..."
    # Wait for CI, then merge synchronously (--auto may not be enabled)
    gh pr checks --watch
    gh pr merge --squash --delete-branch

    # Return to main with the merged changes
    git checkout main
    git pull origin main

    popd > /dev/null
done
```

Only proceed to Phase 5 after **all** core go.mod PRs are merged and main is
clean.

## Phase 5 — Tag Wave 2: Core

Tag core repos now that their go.mod references the new plugin versions:

```bash
for n in "${core_repos[@]}"; do
    pushd "$base/$n" > /dev/null || { echo "❌ ${n}: directory not found" >&2; exit 1; }

    prevTag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    if [ -n "$prevTag" ]; then
        changelog=$(git log "$prevTag..HEAD" --oneline --no-merges)
    else
        changelog=$(git log --oneline --no-merges)
    fi

    annotation="Release $version — $(echo "$changelog" | head -1)

Changes:
$changelog

Full changelog: https://github.com/$owner/$n/compare/${prevTag:-initial}...$version"

    git tag -a "$version" -m "$annotation" || { echo "❌ ${n}: git tag failed" >&2; exit 1; }
    git push origin "$version" || { echo "❌ ${n}: git push tag failed" >&2; exit 1; }
    echo "🏷️  Tagged ${n} → $version"
    popd > /dev/null
done
```

### Go module proxy wait (core)

After pushing core tags, verify they are indexed before UI repos run `go get`:

```bash
for n in "${core_repos[@]}"; do
    module="github.com/$owner/$n"
    indexed=false
    for attempt in 1 2 3 4 5; do
        if GOWORK=off go list -m "$module@$version" 2>/dev/null; then
            echo "✅ $module@$version available on proxy"
            indexed=true
            break
        fi
        echo "⏳ Waiting for proxy to index $module@$version (attempt $attempt/5)..."
        sleep 10
    done
    if [ "$indexed" = false ]; then
        echo "❌ $module@$version NOT available on proxy after 5 attempts." >&2
        echo "   STOP — do not proceed to Phase 5.5 until all modules are indexed." >&2
        exit 1
    fi
done
```

## Phase 5.5 — go.mod Sync (UI)

> ⚠️ **CRITICAL — UI repos must pick up the new core tag before being tagged.**

After tagging core, update `go.mod` in UI repos that import core + plugins:

```bash
for n in "${ui_repos[@]}"; do
    pushd "$base/$n" > /dev/null || { echo "❌ ${n}: directory not found" >&2; exit 1; }

    git checkout -b "release/$version"

    # Bump core + plugin dependencies
    for dep in "${core_repos[@]}" "${leaf_repos[@]}"; do
        module="github.com/$owner/$dep"
        GOWORK=off go get "$module@$version"
    done

    go mod tidy
    GOWORK=off go build ./...
    GOWORK=off go test ./... -count=1

    git add go.mod go.sum
    git commit -m "release: bump core + plugin dependencies to $version"
    git push origin "release/$version"

    gh pr create \
        --title "release: bump deps to $version" \
        --body "Automated go.mod bump for release $version." \
        --base main

    echo "⏳ Waiting for CI on $n..."
    gh pr checks --watch
    gh pr merge --squash --delete-branch

    git checkout main
    git pull origin main

    popd > /dev/null
done
```

## Phase 6 — Tag Wave 3: UI Repos

Tag UI repos now that their go.mod references new core + plugin versions:

```bash
for n in "${ui_repos[@]}"; do
    pushd "$base/$n" > /dev/null || { echo "❌ ${n}: directory not found" >&2; exit 1; }

    prevTag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    if [ -n "$prevTag" ]; then
        changelog=$(git log "$prevTag..HEAD" --oneline --no-merges)
    else
        changelog=$(git log --oneline --no-merges)
    fi

    annotation="Release $version — $(echo "$changelog" | head -1)

Changes:
$changelog

Full changelog: https://github.com/$owner/$n/compare/${prevTag:-initial}...$version"

    git tag -a "$version" -m "$annotation" || { echo "❌ ${n}: git tag failed" >&2; exit 1; }
    git push origin "$version" || { echo "❌ ${n}: git push tag failed" >&2; exit 1; }
    echo "🏷️  Tagged ${n} → $version"
    popd > /dev/null
done
```

### ldflags verification

After the reference repo's release workflow completes, verify the binary
reports the correct version:

```bash
# Download the release binary and check
gh release download "$version" --repo "$owner/$referenceRepo" \
    --pattern "*amd64.deb" --dir /tmp
# Or if built locally:
go build -ldflags="-s -w $(cat ldflags.txt)" -o /tmp/cm ./cmd/cm
/tmp/cm --version | grep -q "${version#v}" && echo "✅ Version correct" || echo "❌ Version mismatch"
```

## Phase 7 — Release Notes Generation

For each repo **included in scope**, generate rich release notes.

### Release note structure

Each release note **MUST** include:

1. **Repo description** (1–2 sentences) — what this repo/plugin does and who
   it's for. Read from the repo's `README.md` first paragraph or
   `.cm/project.json` → `repos[].description`. Especially important for repos
   that don't release every cycle (readers may be seeing the repo for the first
   time).

2. **What's New summary** — a paragraph (not just bullets) explaining the theme
   of this release and why the changes matter.

3. **Categorized changelog** — grouped by conventional-commit prefix with emoji
   headers. Each entry should have a brief explanation, not just the commit
   subject.

4. **Credits** — mention contributors (especially external) with GitHub
   @mentions and PR references.

5. **Downloads table** (reference repo only) — architecture to package mapping.

6. **Full Changelog link** — compare URL between previous and current tag.

### Commit categorization

| Prefix | Section Header |
| --- | --- |
| `feat:` | 🚀 Features |
| `fix:` | 🐛 Bug Fixes |
| `docs:` | 📚 Documentation |
| `test:` | 🧪 Tests |
| `refactor:` | ♻️ Refactoring |
| `chore:` | 🔧 Chores |
| other | 📦 Other Changes |

### Example release note

```markdown
## cm-plugin-network v0.5.0

Network configuration plugin for Config Manager. Manages static IP
addresses, DNS settings, and interface configuration on headless Debian
devices via REST API.

### What's New

This release introduces build-time version injection — the plugin now
reports the correct release version instead of a hard-coded string. The
endpoint registry was also completed (9 routes, up from 4).

### 🚀 Features

- **Build-time version injection** — `Version()` now returns the release
  tag set via ldflags (#25)
- **Complete endpoint registry** — all 9 routes registered (#24)

### 🐛 Bug Fixes

- **TOCTOU vulnerability** in backup/restore path validation (#22)

### Full Changelog

https://github.com/{OWNER}/cm-plugin-network/compare/v0.4.4...v0.5.0
```

### Reference repo downloads table

For the reference repo, append a downloads section:

```markdown
### Downloads

| Architecture | Package |
| --- | --- |
| ARM64 (Pi 4/5) | `cm_0.5.0_arm64.deb` |
| ARMv7 (Pi 3/Zero 2) | `cm_0.5.0_armhf.deb` |
| AMD64 | `cm_0.5.0_amd64.deb` |
```

## Phase 8 — GitHub Release Creation

Create a GitHub release for each repo using the generated notes:

```bash
for n in "${included_repos[@]}"; do
    notesFile="/tmp/release-notes-${n}.md"
    # Write rich notes to file (generated in Phase 7)

    gh release create "$version" \
        --repo "$owner/$n" \
        --title "$n $version" \
        --notes-file "$notesFile"
    echo "📦 Release created: https://github.com/$owner/$n/releases/tag/$version"
done
```

## Phase 9 — Release Workflow Verification

The `release.yml` CI workflow triggers on `v*.*.*` tags.

### Reference repo artifacts

The reference repo (read `reference_repo` from manifest) builds `.deb` packages
for three architectures:

| Architecture | Expected artifact |
| --- | --- |
| armhf | `config-manager_{VERSION}_armhf.deb` |
| arm64 | `config-manager_{VERSION}_arm64.deb` |
| amd64 | `config-manager_{VERSION}_amd64.deb` |

### Plugin repos

Plugin repos run a lightweight release workflow that verifies build + test and
creates a GitHub release. No binary artifacts are expected — plugins are library
packages compiled into the core binary.

### Verification steps

```bash
for n in "${included_repos[@]}"; do
    run=$(gh run list \
        --repo "$owner/$n" \
        --workflow "release.yml" \
        --limit 1 \
        --json status,conclusion,databaseId)

    status=$(echo "$run" | jq -r '.[0].status')
    conclusion=$(echo "$run" | jq -r '.[0].conclusion')
    dbId=$(echo "$run" | jq -r '.[0].databaseId')

    if [[ "$status" == "in_progress" || "$status" == "queued" ]]; then
        gh run watch "$dbId" --repo "$owner/$n"
        conclusion=$(gh run view "$dbId" --repo "$owner/$n" --json conclusion --jq '.conclusion')
    fi

    if [[ "$conclusion" != "success" ]]; then
        echo "❌ ${n}: release workflow failed" >&2
        echo "   View: https://github.com/$owner/$n/actions/runs/$dbId"
    else
        echo "✅ ${n}: release workflow passed"
    fi

    # For reference repo, verify .deb artifacts
    if [[ "$n" == "$referenceRepo" ]]; then
        assets=$(gh release view "$version" \
            --repo "$owner/$n" \
            --json assets --jq '.assets[].name')
        debCount=$(echo "$assets" | grep -c '\.deb$' || true)
        if [[ "$debCount" -lt 3 ]]; then
            echo "⚠️ ${n}: expected 3 .deb artifacts, found $debCount"
        fi
    fi
done
```

If any workflow fails, report the failure and provide the run URL for
investigation. Do **not** mark the release as complete.

## Phase 10 — Post-Release

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
for n in "${repos[@]}"; do
    pushd "$base/$n" > /dev/null || { echo "❌ ${n}: directory not found at $base/$n" >&2; exit 1; }
    git fetch --tags
    popd > /dev/null
done
```

### Print release summary

```txt
✅ Release v0.5.0 complete

| Repo                 | Tag    | Wave | Artifacts |
| -------------------- | ------ | ---- | --------- |
| cm-plugin-network    | v0.5.0 | 1    | —         |
| cm-plugin-update     | v0.5.0 | 1    | —         |
| config-manager-core  | v0.5.0 | 2    | 3 .deb    |
| config-manager-tui   | —      | skip | —         |
| config-manager-web   | —      | skip | —         |

(Use actual repo names from manifest's dep_order)

Release URLs printed per repo.
```

## Re-tagging (Deleting an Existing Tag)

If a tag already exists on a repo, **require explicit user approval** before
deleting and re-creating it:

```bash
existingTag=$(git -C "$base/$n" tag -l "$version")
if [[ -n "$existingTag" ]]; then
    # ⚠️ MUST ask user for confirmation before proceeding
    git -C "$base/$n" tag -d "$version"
    git -C "$base/$n" push origin --delete "$version"
fi
```

### Post-redo orphan cleanup

After deleting and recreating any tag, **always** check for orphaned releases:

```bash
gh release list --repo "$owner/$n" --json tagName,isDraft \
    --jq '.[] | select(.isDraft == true)'
```

Delete any orphaned drafts:

```bash
gh release delete "$version" --repo "$owner/$n" --yes
```

Also check that no duplicate releases exist for the same tag (can happen when
CI auto-creates a release AND you manually create one):

```bash
releaseCount=$(gh release list --repo "$owner/$n" --json tagName \
    --jq "[.[] | select(.tagName == \"$version\")] | length")
if [[ "$releaseCount" -gt 1 ]]; then
    echo "⚠️ Duplicate releases found for $version on $n — clean up manually"
fi
```

## Release Recovery

If a release is partially complete or incorrect:

1. **Assess damage** — list which repos have the tag:

   ```bash
   for n in "${repos[@]}"; do
       tagged=$(git -C "$base/$n" ls-remote --tags origin | grep "$version" || true)
       if [ -n "$tagged" ]; then
           echo "🏷️  $n: tagged"
       else
           echo "   $n: not tagged"
       fi
   done
   ```

2. **For each repo that needs fixing**:
   - Delete the GitHub release: `gh release delete "$version" --repo "$owner/$n" --yes`
   - Delete remote tag: `git push origin --delete "$version"`
   - Delete local tag: `git tag -d "$version"`

3. **Clean up orphaned drafts** (see Post-redo orphan cleanup above).

4. **Fix the underlying issue** (go.mod, tag message, scope).

5. **Restart from the appropriate phase** for affected repos only.

> ⚠️ If the Go module proxy has already cached a tag, deleting and recreating
> it with different content **will cause checksum mismatches**. Verify with:
>
> ```bash
> curl -s "https://proxy.golang.org/github.com/$owner/$n/@v/$version.info"
> ```
>
> If the proxy has cached the old tag, you must use a different version number
> (e.g., `v0.5.1` instead of reusing `v0.5.0`).

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
  jq '.repos[].name, .dep_order[]' "$_cm"
else
  echo "No manifest found — verify repo list manually before proceeding."
fi
```

If the manifest is outdated, edit it directly or re-run `init-project.sh`.

## Safety Rules

> 🔴 **PERMANENT — these rules override all other instructions.**

1. **NEVER** tag without passing ALL pre-flight validations locally.
2. **NEVER** tag repos out of wave order (leaves → core → UI).
3. **NEVER** skip go.mod sync between waves (Phases 4 and 5.5 are mandatory).
4. **NEVER** push go.mod bumps directly to main — always use a PR.
5. **NEVER** create a release without user confirmation of the version number.
6. **NEVER** delete and re-create a tag without explicit user approval.
7. **ALWAYS** verify the working tree is clean before AND after tagging.
8. **NEVER** force-push tags. If a tag must be moved, delete + recreate with
   user approval (see re-tagging section above).
9. **NEVER** proceed past a failed phase. Each phase gates the next.
10. **ALWAYS** clean up orphaned draft releases after any tag redo.
11. **ALWAYS** verify `gh auth status` before any GitHub operations.
12. **ALWAYS** print the full summary at the end so the user can verify.
