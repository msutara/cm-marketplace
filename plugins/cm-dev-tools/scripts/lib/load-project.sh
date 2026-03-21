#!/usr/bin/env bash
# load-project.sh — Read project context from $CM_REPO_BASE/.cm/project.json
#
# Source this file to populate:
#   REPO_BASE, OWNER, REPOS[], DEP_ORDER[], REFERENCE_REPO
#   PROJECT_NUMBER, PROJECT_ID, STATUS_FIELD_ID, STATUS_OPTIONS[]
#
# Usage: source "$(dirname "$0")/lib/load-project.sh"

# shellcheck disable=SC2034  # Variables are used by sourcing scripts

# Requires bash 4+ for mapfile and associative arrays
if ((BASH_VERSINFO[0] < 4)); then
  echo "Error: bash 4+ required (for mapfile/associative arrays). Found: $BASH_VERSION" >&2
  echo "  macOS: brew install bash" >&2
  exit 1
fi

REPO_BASE="${CM_REPO_BASE:-$HOME/repo}"
_PROJECT_JSON="$REPO_BASE/.cm/project.json"

if [ ! -f "$_PROJECT_JSON" ]; then
  echo "Error: project manifest not found at $_PROJECT_JSON" >&2
  echo "Create one with: init-project.sh, or see cm-marketplace README." >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required to read the project manifest." >&2
  echo "Install: apt install jq / brew install jq / winget install jqlang.jq" >&2
  exit 1
fi

OWNER=$(jq -r '.owner // empty' "$_PROJECT_JSON")
if [ -z "$OWNER" ]; then
  echo "Error: 'owner' is required in $_PROJECT_JSON" >&2
  exit 1
fi

mapfile -t REPOS < <(jq -r '.repos[].name' "$_PROJECT_JSON")
if [ ${#REPOS[@]} -eq 0 ]; then
  echo "Error: 'repos' array is empty in $_PROJECT_JSON" >&2
  exit 1
fi

REFERENCE_REPO=$(jq -r '.reference_repo // .repos[0].name' "$_PROJECT_JSON")

if jq -e '.dep_order' "$_PROJECT_JSON" &>/dev/null; then
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
  PROJECT_NUMBER=$(jq -r '.project_board.number' "$_PROJECT_JSON")
  PROJECT_ID=$(jq -r '.project_board.id' "$_PROJECT_JSON")
  STATUS_FIELD_ID=$(jq -r '.project_board.status_field_id' "$_PROJECT_JSON")
  while IFS='=' read -r key val; do
    STATUS_OPTIONS["$key"]="$val"
  done < <(jq -r '.project_board.statuses | to_entries[] | "\(.key)=\(.value)"' "$_PROJECT_JSON")
fi
