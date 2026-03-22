#!/usr/bin/env bash
# repo-status.sh — Git status, branch, and last tag for CM repos
# Usage: ./repo-status.sh [--json] [repo-name]
# Intentionally omit -e: script continues through missing/broken repos to show all statuses
set -uo pipefail

JSON_OUTPUT=false
ARGS=()
for arg in "$@"; do
  if [[ "$arg" == "--json" ]]; then
    JSON_OUTPUT=true
  else
    ARGS+=("$arg")
  fi
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

# Helper: log to stderr when in JSON mode, stdout otherwise
log() {
  if $JSON_OUTPUT; then
    echo "$@" >&2
  else
    echo "$@"
  fi
}

if ! command -v git &>/dev/null; then
  if $JSON_OUTPUT; then
    echo '{"ok":false,"tool":"repo-status","data":{"repos":[]},"error":"git is required but not installed."}'
  else
    echo "Error: git is required but not installed." >&2
  fi
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/load-project.sh
if ! source "$SCRIPT_DIR/lib/load-project.sh"; then
  echo "Error: failed to load project manifest." >&2
  if $JSON_OUTPUT; then
    jq -nc '{ok: false, tool: "repo-status", data: null, error: "failed to load project manifest."}'
  fi
  exit 1
fi

if [ "${1:-}" ]; then
  if [[ ! "$1" =~ ^[A-Za-z0-9._-]+$ ]] || [[ "$1" == "." || "$1" == ".." ]]; then
    echo "Error: Invalid repo name: $1" >&2
    if $JSON_OUTPUT; then
      jq -nc --arg error "Invalid repo name: $1" '{ok: false, tool: "repo-status", data: null, error: $error}'
    fi
    exit 1
  fi
  REPOS=("$1")
fi

# JSON accumulator: collect repo entries as JSON array elements
_json_repos=()

for repo in "${REPOS[@]}"; do
  path="$REPO_BASE/$repo"
  if [ ! -d "$path" ]; then
    log "⚠️  $repo — not found"
    continue
  fi

  if ! git -C "$path" rev-parse --is-inside-work-tree &>/dev/null; then
    log "⚠️  $repo — not a git repo"
    continue
  fi

  branch=$(git -C "$path" branch --show-current 2>/dev/null)
  branch="${branch:-(detached)}"
  dirty=$(git -C "$path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  last_tag=$(git -C "$path" describe --tags --abbrev=0 2>/dev/null || true)

  if [ "$dirty" -eq 0 ]; then
    clean_icon="✅"
  else
    clean_icon="⚠️ ($dirty files)"
  fi

  log "$repo"
  log "  Branch:   $branch"
  log "  Clean:    $clean_icon"
  log "  Last tag: ${last_tag:-(none)}"
  log ""

  if $JSON_OUTPUT; then
    _json_repos+=("$(jq -nc \
      --arg name "$repo" \
      --arg branch "$branch" \
      --argjson dirty "$dirty" \
      --arg lastTag "${last_tag:-}" \
      '{
        name: $name,
        branch: $branch,
        clean: ($dirty == 0),
        dirtyFiles: $dirty,
        lastTag: (if $lastTag == "" then null else $lastTag end)
      }')")
  fi
done

if $JSON_OUTPUT; then
  # Assemble the repos array from collected elements
  _repos_json="[]"
  for _entry in "${_json_repos[@]+"${_json_repos[@]}"}"; do
    _repos_json=$(printf '%s' "$_repos_json" | jq -c --argjson e "$_entry" '. + [$e]')
  done
  jq -nc --argjson repos "$_repos_json" '{ok: true, tool: "repo-status", data: {repos: $repos}, error: null}'
fi
