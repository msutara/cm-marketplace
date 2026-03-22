#!/usr/bin/env bash
# sync-deps.sh — Bump a go.mod dependency across downstream CM repos
# Usage: ./sync-deps.sh <source-module> <version> [--json]
# Example: ./sync-deps.sh github.com/{OWNER}/config-manager-core v0.5.0
set -euo pipefail

# Parse --json early (before any validation) so JSON_OUTPUT is available for all error paths
JSON_OUTPUT=false
_positional_args=()
for arg in "$@"; do
  case "$arg" in
    --json) JSON_OUTPUT=true ;;
    --*)
      echo "Error: unknown option: $arg" >&2
      if $JSON_OUTPUT; then
        jq -nc --arg error "unknown option: $arg" '{ok: false, tool: "sync-deps", data: null, error: $error}'
      fi
      exit 1 ;;
    *) _positional_args+=("$arg") ;;
  esac
done

SOURCE_MODULE="${_positional_args[0]:-}"
VERSION="${_positional_args[1]:-}"

if [ -z "$SOURCE_MODULE" ] || [ -z "$VERSION" ]; then
  echo "Usage: sync-deps.sh <source-module> <version> [--json]" >&2
  if $JSON_OUTPUT; then
    jq -nc '{ok: false, tool: "sync-deps", data: null, error: "missing required arguments: source-module and version"}'
  fi
  exit 1
fi

if ! command -v go &>/dev/null; then
  echo "Error: go is required but not installed. See: https://go.dev/dl/" >&2
  if $JSON_OUTPUT; then
    jq -nc '{ok: false, tool: "sync-deps", data: null, error: "go is required but not installed."}'
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

# Validate inputs to prevent command injection
if [[ ! "$SOURCE_MODULE" =~ ^[a-zA-Z0-9][a-zA-Z0-9._/-]*$ ]] || [[ "$SOURCE_MODULE" == *..* ]]; then
  echo "Error: Invalid source module format: $SOURCE_MODULE" >&2
  if $JSON_OUTPUT; then
    jq -nc --arg error "Invalid source module format: $SOURCE_MODULE" '{ok: false, tool: "sync-deps", data: null, error: $error}'
  fi
  exit 1
fi
# Allow semver (vX.Y.Z[-prerelease][+build]) and Go pseudo-versions (vX.Y.Z-yyyymmddhhmmss-abcdefabcdef)
semver_re='^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'
pseudo_re='^v[0-9]+\.[0-9]+\.[0-9]+-(0\.)?[0-9]{14}-[0-9a-f]{7,}$'
if [[ ! "$VERSION" =~ $semver_re && ! "$VERSION" =~ $pseudo_re ]]; then
  echo "Error: Invalid version format: $VERSION (expected semver vX.Y.Z[-prerelease][+build] or Go pseudo-version)" >&2
  if $JSON_OUTPUT; then
    jq -nc --arg error "Invalid version format: $VERSION" '{ok: false, tool: "sync-deps", data: null, error: $error}'
  fi
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/load-project.sh
source "$SCRIPT_DIR/lib/load-project.sh"

UPDATED=()
ERRORS=()
_tmp_files=()
# shellcheck disable=SC2317,SC2329
cleanup() { if [[ ${#_tmp_files[@]} -gt 0 ]]; then rm -f "${_tmp_files[@]}"; fi; }
trap cleanup EXIT INT TERM

# JSON accumulators
_json_repos=()

for repo in "${REPOS[@]}"; do
  path="$REPO_BASE/$repo"
  gomod="$path/go.mod"

  [ ! -f "$gomod" ] && continue

  # Skip if this repo doesn't import the source module
  if ! grep -Fq "$SOURCE_MODULE" "$gomod"; then
    continue
  fi

  # Skip self (the module that was just updated)
  module_line=$(grep -m1 '^module[[:space:]]' "$gomod" || true)
  if [ -z "$module_line" ]; then
    continue
  fi
  module_name=$(echo "$module_line" | sed 's/^module[[:space:]]*//' | tr -d '[:space:]')
  if [ "$module_name" = "$SOURCE_MODULE" ]; then
    _json_repos+=("$(jq -nc --arg name "$repo" '{name: $name, updated: false, skipped: true, reason: "source module"}')")
    continue
  fi

  log "Updating $repo..."
  pushd "$path" > /dev/null

  tmp_err=$(mktemp "${TMPDIR:-/tmp}/cm-sync-deps.XXXXXX"); _tmp_files+=("$tmp_err")
  if ! go get "${SOURCE_MODULE}@${VERSION}" 2>"$tmp_err"; then
    ERRORS+=("$repo: go get failed: $(<"$tmp_err")")
    _json_repos+=("$(jq -nc --arg name "$repo" --arg reason "go get failed" '{name: $name, updated: false, skipped: false, reason: $reason}')")
    popd > /dev/null
    continue
  fi

  tmp_err=$(mktemp "${TMPDIR:-/tmp}/cm-sync-deps.XXXXXX"); _tmp_files+=("$tmp_err")
  if ! go mod tidy 2>"$tmp_err"; then
    ERRORS+=("$repo: go mod tidy failed: $(<"$tmp_err")")
    _json_repos+=("$(jq -nc --arg name "$repo" --arg reason "go mod tidy failed" '{name: $name, updated: false, skipped: false, reason: $reason}')")
    popd > /dev/null
    continue
  fi

  log "  ✅ $repo updated to ${SOURCE_MODULE}@${VERSION}"
  UPDATED+=("$repo")
  _json_repos+=("$(jq -nc --arg name "$repo" '{name: $name, updated: true}')")
  popd > /dev/null
done

log ""
log "=== Summary ==="
if [ ${#UPDATED[@]} -gt 0 ]; then
  log "Updated: ${UPDATED[*]}"
else
  log "Updated: none"
fi
if [ ${#ERRORS[@]} -gt 0 ]; then
  echo "Errors:" >&2
  for err in "${ERRORS[@]}"; do
    echo "  ❌ $err" >&2
  done
  if $JSON_OUTPUT; then
    _repos_json="[]"
    for _entry in "${_json_repos[@]+"${_json_repos[@]}"}"; do
      _repos_json=$(printf '%s' "$_repos_json" | jq -c --argjson e "$_entry" '. + [$e]')
    done
    _err_summary="${#ERRORS[@]} repo(s) failed during dependency sync"
    jq -nc \
      --arg module "$SOURCE_MODULE" \
      --arg version "$VERSION" \
      --argjson repos "$_repos_json" \
      --arg error "$_err_summary" \
      '{ok: false, tool: "sync-deps", data: {module: $module, version: $version, repos: $repos}, error: $error}'
  fi
  exit 1
fi

if $JSON_OUTPUT; then
  _repos_json="[]"
  for _entry in "${_json_repos[@]+"${_json_repos[@]}"}"; do
    _repos_json=$(printf '%s' "$_repos_json" | jq -c --argjson e "$_entry" '. + [$e]')
  done
  jq -nc \
    --arg module "$SOURCE_MODULE" \
    --arg version "$VERSION" \
    --argjson repos "$_repos_json" \
    '{ok: true, tool: "sync-deps", data: {module: $module, version: $version, repos: $repos}, error: null}'
fi
