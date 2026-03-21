#!/usr/bin/env bash
# init-project.sh — Generate $CM_REPO_BASE/.cm/project.json interactively
# Usage: ./init-project.sh
set -euo pipefail

REPO_BASE="${CM_REPO_BASE:-$HOME/repo}"
TARGET_DIR="$REPO_BASE/.cm"
TARGET_FILE="$TARGET_DIR/project.json"

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
if [ -z "$owner" ]; then
  echo "Error: owner is required." >&2
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
  if [[ "$repo_input" == *:* ]]; then
    role="${repo_input#*:}"
  else
    role=""
  fi
  repos+=("$repo")
  roles+=("$role")
done

if [ ${#repos[@]} -eq 0 ]; then
  echo "Error: at least one repo is required." >&2
  exit 1
fi

read -rp "Reference repo [${repos[0]}]: " ref_repo
ref_repo="${ref_repo:-${repos[0]}}"

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
else
  dep_order=("${repos[@]}")
fi

echo ""
echo "GitHub project board (optional — press Enter to skip):"
read -rp "  project number: " proj_num

mkdir -p "$TARGET_DIR"

# Build JSON with jq
repos_json="[]"
for i in "${!repos[@]}"; do
  repos_json=$(echo "$repos_json" | jq --arg n "${repos[$i]}" --arg r "${roles[$i]}" '. + [{name: $n, role: $r}]')
done
dep_json=$(printf '%s\n' "${dep_order[@]}" | jq -R '.' | jq -s '.')

if [ -n "$proj_num" ]; then
  read -rp "  project ID (PVT_...): " proj_id
  read -rp "  status field ID (PVTSSF_...): " status_field
  echo "  Status options (key=value, one per line, empty to finish):"
  statuses="{}"
  while true; do
    read -rp "    " kv
    [ -z "$kv" ] && break
    key="${kv%%=*}"
    val="${kv#*=}"
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
