#!/usr/bin/env bash
# load-project.sh — Read project context from $CM_REPO_BASE/.cm/project.json
#
# Source this file to populate:
#   REPO_BASE, OWNER, REPOS[], DEP_ORDER[], REFERENCE_REPO
#   PROJECT_NUMBER, PROJECT_ID, STATUS_FIELD_ID, STATUS_OPTIONS (map: status name → option id)
#
# Usage: source "$(dirname "$0")/lib/load-project.sh"

# shellcheck disable=SC2034  # Variables are used by sourcing scripts
# shellcheck disable=SC2317  # exit after return is fallback for non-sourced execution

# Requires bash 4+ for mapfile and associative arrays
if ((BASH_VERSINFO[0] < 4)); then
  echo "Error: bash 4+ required (for mapfile/associative arrays). Found: $BASH_VERSION" >&2
  echo "  macOS: brew install bash" >&2
  return 1 2>/dev/null || exit 1
fi

# Discover REPO_BASE: explicit env var → walk up from CWD → $HOME/repo fallback
_find_repo_base() {
  # 1. Explicit env var — fail if set but invalid
  if [ -n "${CM_REPO_BASE:-}" ]; then
    if [ -f "$CM_REPO_BASE/.cm/project.json" ]; then
      echo "$CM_REPO_BASE"
      return
    fi
    echo "Error: CM_REPO_BASE is set to '$CM_REPO_BASE' but .cm/project.json not found there." >&2
    return 1
  fi
  # 2. Walk up from CWD looking for .cm/project.json
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/.cm/project.json" ]; then
      echo "$dir"
      return
    fi
    # Also check parent (repos are siblings under the base)
    local parent
    parent="$(dirname "$dir")"
    if [ -f "$parent/.cm/project.json" ]; then
      echo "$parent"
      return
    fi
    dir="$parent"
  done
  # 3. Fallback
  if [ -f "$HOME/repo/.cm/project.json" ]; then
    echo "$HOME/repo"
    return
  fi
  echo "Error: project manifest not found." >&2
  echo "Searched: \$CM_REPO_BASE, parent directories of CWD, \$HOME/repo" >&2
  echo "Create one with: init-project.sh, or see cm-marketplace README." >&2
  return 1
}

REPO_BASE="$(_find_repo_base)"
if [ -z "$REPO_BASE" ]; then
  # Function already printed error details
  return 1 2>/dev/null || exit 1
fi
_PROJECT_JSON="$REPO_BASE/.cm/project.json"

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required to read the project manifest." >&2
  echo "Install: apt install jq / brew install jq / winget install jqlang.jq" >&2
  return 1 2>/dev/null || exit 1
fi

OWNER=$(jq -r '.owner // empty' "$_PROJECT_JSON")
if [ -z "$OWNER" ]; then
  echo "Error: 'owner' is required in $_PROJECT_JSON" >&2
  return 1 2>/dev/null || exit 1
fi
if [[ ! "$OWNER" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]]; then
  echo "Error: 'owner' ($OWNER) contains invalid characters in $_PROJECT_JSON. GitHub logins must start with [A-Za-z0-9] and use [A-Za-z0-9-]." >&2
  return 1 2>/dev/null || exit 1
fi

# Validate repos: non-empty array with unique, non-empty .name entries
if ! jq -e '
  .repos
  and (.repos | type == "array")
  and (.repos | length > 0)
  and all(.repos[]; (.name | type == "string" and . != "" and test("^[A-Za-z0-9][A-Za-z0-9._-]*$")))
  and ((.repos | map(.name) | unique | length) == (.repos | length))
' "$_PROJECT_JSON" >/dev/null; then
  echo "Error: 'repos' must be a non-empty array; each 'name' must start with [A-Za-z0-9], be unique, and match [A-Za-z0-9._-]+ in $_PROJECT_JSON" >&2
  return 1 2>/dev/null || exit 1
fi

mapfile -t REPOS < <(jq -r '.repos[].name' "$_PROJECT_JSON")

REFERENCE_REPO=$(jq -r '.reference_repo // .repos[0].name' "$_PROJECT_JSON")

# Validate reference_repo is in repos[]
if ! printf '%s\n' "${REPOS[@]}" | grep -qxF "$REFERENCE_REPO"; then
  echo "Error: 'reference_repo' ($REFERENCE_REPO) is not in 'repos' in $_PROJECT_JSON" >&2
  return 1 2>/dev/null || exit 1
fi

if jq -e 'has("dep_order")' "$_PROJECT_JSON" &>/dev/null; then
  if ! jq -e '
    (.dep_order | type == "array")
    and (.dep_order | length > 0)
    and all(.dep_order[]; type == "string" and . != "")
  ' "$_PROJECT_JSON" >/dev/null; then
    echo "Error: 'dep_order' must be a non-empty array of non-empty strings in $_PROJECT_JSON" >&2
    return 1 2>/dev/null || exit 1
  fi
  # Validate dep_order is an exact permutation of repos (unique + complete)
  if ! jq -e '
    [.repos[].name] as $names |
    (.dep_order | length == ($names | length))
    and (.dep_order | unique | length == (.dep_order | length))
    and all(.dep_order[]; . as $d | any($names[]; . == $d))
  ' "$_PROJECT_JSON" >/dev/null; then
    echo "Error: 'dep_order' must be a permutation of 'repos' (same entries, same count) in $_PROJECT_JSON" >&2
    return 1 2>/dev/null || exit 1
  fi
  mapfile -t DEP_ORDER < <(jq -r '.dep_order[]' "$_PROJECT_JSON")
else
  DEP_ORDER=("${REPOS[@]}")
fi

# Project board (optional — only populated if present in manifest)
PROJECT_NUMBER=""
PROJECT_ID=""
STATUS_FIELD_ID=""
declare -A STATUS_OPTIONS 2>/dev/null || true

if jq -e '.project_board' "$_PROJECT_JSON" &>/dev/null; then
  PROJECT_NUMBER=$(jq -r '.project_board.number // empty' "$_PROJECT_JSON")
  PROJECT_ID=$(jq -r '.project_board.id // empty' "$_PROJECT_JSON")
  STATUS_FIELD_ID=$(jq -r '.project_board.status_field_id // empty' "$_PROJECT_JSON")
  if [ -z "$PROJECT_NUMBER" ] || [ -z "$PROJECT_ID" ] || [ -z "$STATUS_FIELD_ID" ]; then
    echo "Error: When 'project_board' is defined, 'number', 'id', and 'status_field_id' must all be set in $_PROJECT_JSON" >&2
    return 1 2>/dev/null || exit 1
  fi
  if ! [[ "$PROJECT_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: 'project_board.number' must be a positive integer in $_PROJECT_JSON (got: $PROJECT_NUMBER)" >&2
    return 1 2>/dev/null || exit 1
  fi
  if jq -e '.project_board.statuses' "$_PROJECT_JSON" &>/dev/null; then
    while IFS='=' read -r key val; do
      STATUS_OPTIONS["$key"]="$val"
    done < <(jq -r '.project_board.statuses | to_entries[] | "\(.key)=\(.value)"' "$_PROJECT_JSON")
  fi
fi
