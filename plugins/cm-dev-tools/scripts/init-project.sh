#!/usr/bin/env bash
# init-project.sh — Generate $CM_REPO_BASE/.cm/project.json interactively
# Usage: ./init-project.sh
set -euo pipefail

if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  echo "Error: bash 4+ required (you have $BASH_VERSION). Install a newer bash." >&2
  exit 1
fi

default_base="${CM_REPO_BASE:-$HOME/repo}"
read -rp "Repo base directory [$default_base]: " user_base
user_base="${user_base#"${user_base%%[![:space:]]*}"}"
user_base="${user_base%"${user_base##*[![:space:]]}"}"
REPO_BASE="${user_base:-$default_base}"
# Expand leading ~ to $HOME (tilde doesn't expand in variables)
# shellcheck disable=SC2088
if [[ "${REPO_BASE:0:2}" == "~/" ]]; then
  REPO_BASE="$HOME/${REPO_BASE:2}"
elif [[ "$REPO_BASE" == "~" ]]; then
  REPO_BASE="$HOME"
fi
if [ ! -d "$REPO_BASE" ]; then
  echo "Error: directory '$REPO_BASE' does not exist." >&2
  exit 1
fi
TARGET_DIR="$REPO_BASE/.cm"
TARGET_FILE="$TARGET_DIR/project.json"

if ! command -v jq &>/dev/null; then
  echo "Error: jq is required to generate the manifest." >&2
  echo "Install: apt install jq / brew install jq / winget install jqlang.jq" >&2
  exit 1
fi

if [ -f "$TARGET_FILE" ]; then
  echo "project.json already exists at $TARGET_FILE"
  echo "Edit it directly or delete it to regenerate."
  exit 0
fi

echo "=== CM Project Manifest Setup ==="
echo ""
echo "This creates $TARGET_FILE with your project context."
echo "All CM marketplace scripts and skills read from this file."
echo ""

read -rp "GitHub owner (e.g., msutara): " owner
owner="${owner#"${owner%%[![:space:]]*}"}"
owner="${owner%"${owner##*[![:space:]]}"}"
if [ -z "$owner" ]; then
  echo "Error: owner is required." >&2
  exit 1
fi
if [[ ! "$owner" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]]; then
  echo "Error: invalid owner '$owner'. GitHub logins must start with [A-Za-z0-9] and use [A-Za-z0-9-] only." >&2
  exit 1
fi

echo ""
echo "Enter repo names (one per line, empty line to finish):"
echo "  Optionally add a role after a colon, e.g.: config-manager-tui:TUI"
repos=()
roles=()
while true; do
  read -rp "  repo: " repo_input
  [ -z "$repo_input" ] && break
  repo="${repo_input%%:*}"
  # Trim whitespace from repo name
  repo="${repo#"${repo%%[![:space:]]*}"}"
  repo="${repo%"${repo##*[![:space:]]}"}"
  if [ -z "$repo" ]; then
    echo "    ⚠️  Empty repo name — skipped" >&2
    continue
  fi
  if [[ ! "$repo" =~ ^[A-Za-z0-9._-]+$ ]] || [[ "$repo" == "." || "$repo" == ".." ]]; then
    echo "    ⚠️  Invalid repo name '$repo' — must match [A-Za-z0-9._-]+ and not be '.' or '..'" >&2
    continue
  fi
  if [[ "$repo_input" == *:* ]]; then
    role="${repo_input#*:}"
    role="${role#"${role%%[![:space:]]*}"}"
    role="${role%"${role##*[![:space:]]}"}"
  else
    role=""
  fi
  repos+=("$repo")
  roles+=("$role")
done

# Check for duplicate repos
declare -A _seen_repos
for r in "${repos[@]}"; do
  if [[ -n "${_seen_repos[$r]:-}" ]]; then
    echo "Error: duplicate repo '$r'." >&2
    exit 1
  fi
  _seen_repos["$r"]=1
done

if [ ${#repos[@]} -eq 0 ]; then
  echo "Error: at least one repo is required." >&2
  exit 1
fi

read -rp "Reference repo [${repos[0]}]: " ref_repo
ref_repo="${ref_repo:-${repos[0]}}"
ref_repo="${ref_repo#"${ref_repo%%[![:space:]]*}"}"
ref_repo="${ref_repo%"${ref_repo##*[![:space:]]}"}"
# Validate reference_repo is in repos list
_ref_found=false
for r in "${repos[@]}"; do
  [ "$r" = "$ref_repo" ] && _ref_found=true && break
done
if [ "$_ref_found" = false ]; then
  echo "Error: reference repo '$ref_repo' is not in the repos list." >&2
  exit 1
fi

echo ""
echo "Dependency order (comma-separated, or press Enter to use input order):"
read -rp "  dep_order: " dep_input
if [ -n "$dep_input" ]; then
  IFS=',' read -ra _raw_deps <<< "$dep_input"
  dep_order=()
  for d in "${_raw_deps[@]}"; do
    trimmed="${d#"${d%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    dep_order+=("$trimmed")
  done
  # Validate dep_order entries are in repos list and no duplicates
  declare -A _seen_deps
  for dep in "${dep_order[@]}"; do
    if [ -n "${_seen_deps[$dep]+x}" ]; then
      echo "Error: duplicate dep_order entry '$dep'." >&2
      exit 1
    fi
    _seen_deps[$dep]=1
    _found=false
    for r in "${repos[@]}"; do
      [ "$r" = "$dep" ] && _found=true && break
    done
    if [ "$_found" = false ]; then
      echo "Error: dep_order entry '$dep' is not in the repos list." >&2
      exit 1
    fi
  done
  if [ "${#dep_order[@]}" -ne "${#repos[@]}" ]; then
    echo "Error: dep_order must cover all repos (${#dep_order[@]} entries vs ${#repos[@]} repos)." >&2
    exit 1
  fi
else
  dep_order=("${repos[@]}")
fi

echo ""
echo "GitHub project board (optional — press Enter to skip):"
read -rp "  project number: " proj_num
proj_num="${proj_num#"${proj_num%%[![:space:]]*}"}"
proj_num="${proj_num%"${proj_num##*[![:space:]]}"}"
if [ -n "$proj_num" ] && ! [[ "$proj_num" =~ ^[1-9][0-9]*$ ]]; then
  echo "Error: project number must be a positive integer (>= 1)." >&2
  exit 1
fi

mkdir -p "$TARGET_DIR"

# Build JSON with jq
repos_json="[]"
for i in "${!repos[@]}"; do
  repos_json=$(echo "$repos_json" | jq --arg n "${repos[$i]}" --arg r "${roles[$i]}" '. + [{name: $n, role: $r}]')
done
dep_json=$(printf '%s\n' "${dep_order[@]}" | jq -R '.' | jq -s '.')

if [ -n "$proj_num" ]; then
  _id_re='^[A-Za-z0-9+/=_-]+$'
  read -rp "  project ID (PVT_...): " proj_id
  proj_id="${proj_id#"${proj_id%%[![:space:]]*}"}"
  proj_id="${proj_id%"${proj_id##*[![:space:]]}"}"
  read -rp "  status field ID (PVTSSF_...): " status_field
  status_field="${status_field#"${status_field%%[![:space:]]*}"}"
  status_field="${status_field%"${status_field##*[![:space:]]}"}"
  if [ -z "$proj_id" ] || [ -z "$status_field" ]; then
    echo "Error: project ID and status field ID are required when project number is set." >&2
    exit 1
  fi
  if [[ ! "$proj_id" =~ $_id_re ]]; then
    echo "Error: invalid project ID format '$proj_id'." >&2
    exit 1
  fi
  if [[ ! "$status_field" =~ $_id_re ]]; then
    echo "Error: invalid status field ID format '$status_field'." >&2
    exit 1
  fi
  echo "  Status options (key=value, one per line, empty to finish):"
  statuses="{}"
  while true; do
    read -rp "    " kv
    [ -z "$kv" ] && break
    if [[ "$kv" != *=* ]]; then
      echo "    ⚠️  Invalid format (expected key=value): $kv" >&2
      continue
    fi
    key="${kv%%=*}"
    val="${kv#*=}"
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"
    if [ -z "$key" ] || [ -z "$val" ]; then
      echo "    ⚠️  Empty key or value — skipped: $kv" >&2
      continue
    fi
    if [[ ! "$val" =~ $_id_re ]]; then
      echo "    ⚠️  Invalid status option ID format '$val' — skipped: $kv" >&2
      continue
    fi
    statuses=$(echo "$statuses" | jq --arg k "$key" --arg v "$val" '. + {($k): $v}')
  done

  jq -n \
    --arg owner "$owner" \
    --arg ref "$ref_repo" \
    --argjson repos "$repos_json" \
    --argjson dep "$dep_json" \
    --argjson num "$proj_num" \
    --arg pid "$proj_id" \
    --arg sfid "$status_field" \
    --argjson statuses "$statuses" \
    '{
      owner: $owner,
      reference_repo: $ref,
      repos: $repos,
      dep_order: $dep,
      project_board: {
        number: $num,
        id: $pid,
        status_field_id: $sfid,
        statuses: $statuses
      }
    }' > "$TARGET_FILE"
else
  jq -n \
    --arg owner "$owner" \
    --arg ref "$ref_repo" \
    --argjson repos "$repos_json" \
    --argjson dep "$dep_json" \
    '{
      owner: $owner,
      reference_repo: $ref,
      repos: $repos,
      dep_order: $dep
    }' > "$TARGET_FILE"
fi

echo ""
echo "✅ Created $TARGET_FILE"
echo ""
jq '.' "$TARGET_FILE"
