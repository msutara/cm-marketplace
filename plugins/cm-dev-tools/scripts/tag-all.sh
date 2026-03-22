#!/usr/bin/env bash
# tag-all.sh — Tag all CM repos in dependency order from the project manifest
# Usage: ./tag-all.sh <version> [--dry-run] [--json]
set -euo pipefail

# Parse flags early (before any validation) so JSON_OUTPUT is available for all error paths
JSON_OUTPUT=false
# Pre-scan for --json so all error paths can emit JSON
for arg in "$@"; do
  if [ "$arg" = "--json" ]; then JSON_OUTPUT=true; break; fi
done
if $JSON_OUTPUT && ! command -v jq &>/dev/null; then
  printf '{"ok":false,"tool":"tag-all","data":null,"error":"jq is required for --json output but is not installed"}\n'
  exit 1
fi
DRY_RUN=false
_positional_args=()
for arg in "$@"; do
  case "$arg" in
    --json) JSON_OUTPUT=true ;;
    --dry-run) DRY_RUN=true ;;
    --*)
      echo "Error: unknown option: $arg" >&2
      if $JSON_OUTPUT; then
        jq -nc --arg error "unknown option: $arg" '{ok: false, tool: "tag-all", data: null, error: $error}'
      fi
      exit 1 ;;
    *) _positional_args+=("$arg") ;;
  esac
done

if [ ${#_positional_args[@]} -gt 1 ]; then
  echo "Error: too many positional arguments (expected at most 1: version)" >&2
  if $JSON_OUTPUT; then
    jq -nc --arg error "too many positional arguments (expected at most 1: version)" '{ok: false, tool: "tag-all", data: null, error: $error}'
  fi
  exit 1
fi

VERSION="${_positional_args[0]:-}"
if [ -z "$VERSION" ]; then
  echo "Usage: tag-all.sh <version> [--dry-run] [--json]" >&2
  if $JSON_OUTPUT; then
    jq -nc '{ok: false, tool: "tag-all", data: null, error: "missing required argument: version"}'
  fi
  exit 1
fi

if ! command -v git &>/dev/null; then
  echo "Error: git is required but not installed." >&2
  if $JSON_OUTPUT; then
    jq -nc '{ok: false, tool: "tag-all", data: null, error: "git is required but not installed."}'
  fi
  exit 1
fi

# Helper: log to stderr when in JSON mode, stdout otherwise
log() {
  if $JSON_OUTPUT; then
    echo "$@" >&2
  else
    echo "$@"
  fi
}
logf() {
  if $JSON_OUTPUT; then
    # shellcheck disable=SC2059
    printf "$@" >&2
  else
    # shellcheck disable=SC2059
    printf "$@"
  fi
}

if ! [[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: Version must be semver format: v{MAJOR}.{MINOR}.{PATCH}" >&2
  if $JSON_OUTPUT; then
    jq -nc --arg v "$VERSION" --argjson dryRun "$DRY_RUN" '{ok: false, tool: "tag-all", data: {version: $v, dryRun: $dryRun, repos: []}, error: "Version must be semver format: v{MAJOR}.{MINOR}.{PATCH}"}'
  fi
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/load-project.sh
if ! source "$SCRIPT_DIR/lib/load-project.sh"; then
  echo "Error: failed to load project manifest." >&2
  if $JSON_OUTPUT; then
    printf '{"ok":false,"tool":"tag-all","data":null,"error":"failed to load project manifest."}\n'
  fi
  exit 1
fi

# JSON accumulators
_json_repos=()
_overall=0

for repo in "${DEP_ORDER[@]}"; do
  path="$REPO_BASE/$repo"
  if [ ! -d "$path" ]; then
    echo "Error: $repo not found at $path" >&2
    if $JSON_OUTPUT; then
      jq -nc \
        --arg v "$VERSION" \
        --argjson dry "$DRY_RUN" \
        --arg error "$repo not found at $path" \
        '{ok: false, tool: "tag-all", data: {version: $v, dryRun: $dry, repos: []}, error: $error}'
    fi
    exit 1
  fi

  # Verify clean working tree
  if [ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]; then
    echo "Error: $repo has uncommitted changes — aborting" >&2
    if $JSON_OUTPUT; then
      jq -nc \
        --arg v "$VERSION" \
        --argjson dry "$DRY_RUN" \
        --arg error "$repo has uncommitted changes" \
        '{ok: false, tool: "tag-all", data: {version: $v, dryRun: $dry, repos: []}, error: $error}'
    fi
    exit 1
  fi

  # Verify on main branch (empty means detached HEAD)
  branch=$(git -C "$path" branch --show-current 2>/dev/null)
  if [ -z "$branch" ]; then
    echo "Error: $repo is in detached HEAD state — aborting" >&2
    if $JSON_OUTPUT; then
      jq -nc \
        --arg v "$VERSION" \
        --argjson dry "$DRY_RUN" \
        --arg error "$repo is in detached HEAD state" \
        '{ok: false, tool: "tag-all", data: {version: $v, dryRun: $dry, repos: []}, error: $error}'
    fi
    exit 1
  fi
  if [ "$branch" != "main" ]; then
    echo "Error: $repo is on branch '$branch', not 'main' — aborting" >&2
    if $JSON_OUTPUT; then
      jq -nc \
        --arg v "$VERSION" \
        --argjson dry "$DRY_RUN" \
        --arg error "$repo is on branch '$branch', not 'main'" \
        '{ok: false, tool: "tag-all", data: {version: $v, dryRun: $dry, repos: []}, error: $error}'
    fi
    exit 1
  fi

  # Skip if already tagged at this version (check local + remote)
  if git -C "$path" tag -l "$VERSION" | grep -q .; then
    # Local tag exists — ensure remote has it too, then skip
    _remote_tags=$(git -C "$path" ls-remote --tags origin "refs/tags/$VERSION" 2>/dev/null || true)
    if [ -z "$_remote_tags" ]; then
      if [ "$DRY_RUN" = true ]; then
        log "  [DRY RUN] Would push existing local tag $VERSION for $repo"
        _json_repos+=("$(jq -nc --arg name "$repo" --arg tag "$VERSION" '{name: $name, action: "would_push", tag: $tag}')")
      else
        log "  📤 $repo has local tag $VERSION but not on remote — pushing..."
        if ! _git_out=$(git -C "$path" push origin "$VERSION" 2>&1); then
          echo "Error: failed to push tag $VERSION for $repo" >&2
          echo "$_git_out" >&2
          if $JSON_OUTPUT; then
            jq -nc --arg error "failed to push existing tag $VERSION for $repo" \
              '{ok: false, tool: "tag-all", data: null, error: $error}'
          fi
          exit 1
        fi
        _json_repos+=("$(jq -nc --arg name "$repo" --arg tag "$VERSION" '{name: $name, action: "pushed", tag: $tag}')")
      fi
    else
      _json_repos+=("$(jq -nc --arg name "$repo" --arg tag "$VERSION" '{name: $name, action: "skipped", tag: $tag}')")
    fi
    log "  ⏭️  $repo already tagged at $VERSION — skipping"
    continue
  fi
  git -C "$path" fetch --tags --quiet 2>/dev/null || true
  _remote_check=$(git -C "$path" ls-remote --tags origin "refs/tags/$VERSION" 2>/dev/null || true)
  if [ -n "$_remote_check" ]; then
    log "  ⏭️  $repo already tagged at $VERSION (remote) — skipping"
    _json_repos+=("$(jq -nc --arg name "$repo" --arg tag "$VERSION" '{name: $name, action: "skipped", tag: $tag}')")
    continue
  fi

  if [ "$DRY_RUN" = true ]; then
    log "[DRY RUN] Would tag $repo at $VERSION"
    _json_repos+=("$(jq -nc --arg name "$repo" --arg tag "$VERSION" '{name: $name, action: "would_tag", tag: $tag}')")
  else
    log "Tagging $repo at $VERSION..."
    if ! _git_out=$(git -C "$path" tag "$VERSION" 2>&1); then
      echo "Error: failed to create tag $VERSION for $repo" >&2
      echo "$_git_out" >&2
      if $JSON_OUTPUT; then
        jq -nc --arg error "failed to create tag $VERSION for $repo" \
          '{ok: false, tool: "tag-all", data: null, error: $error}'
      fi
      exit 1
    fi
    if ! _git_out=$(git -C "$path" push origin "$VERSION" 2>&1); then
      echo "Error: failed to push tag $VERSION for $repo" >&2
      echo "$_git_out" >&2
      if $JSON_OUTPUT; then
        jq -nc --arg error "failed to push tag $VERSION for $repo" \
          '{ok: false, tool: "tag-all", data: null, error: $error}'
      fi
      exit 1
    fi
    log "  ✅ $repo tagged and pushed $VERSION"
    _json_repos+=("$(jq -nc --arg name "$repo" --arg tag "$VERSION" '{name: $name, action: "tagged", tag: $tag}')")
  fi
done

if [ "$DRY_RUN" = true ]; then
  logf "\n✅ [DRY RUN] All repos would be tagged at %s\n" "$VERSION"
else
  logf "\n✅ All repos tagged at %s\n" "$VERSION"
fi

if $JSON_OUTPUT; then
  _repos_json="[]"
  for _entry in "${_json_repos[@]+"${_json_repos[@]}"}"; do
    _repos_json=$(printf '%s' "$_repos_json" | jq -c --argjson e "$_entry" '. + [$e]')
  done
  jq -nc \
    --arg version "$VERSION" \
    --argjson dryRun "$DRY_RUN" \
    --argjson repos "$_repos_json" \
    '{ok: true, tool: "tag-all", data: {version: $version, dryRun: $dryRun, repos: $repos}, error: null}'
fi
