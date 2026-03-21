#!/usr/bin/env bash
# repo-status.sh — Git status, branch, and last tag for CM repos
# Usage: ./repo-status.sh [repo-name]
# Intentionally omit -e: script continues through missing/broken repos to show all statuses
set -uo pipefail

if ! command -v git &>/dev/null; then
  echo "Error: git is required but not installed." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/load-project.sh
source "$SCRIPT_DIR/lib/load-project.sh"

if [ "${1:-}" ]; then
  REPOS=("$1")
fi

for repo in "${REPOS[@]}"; do
  path="$REPO_BASE/$repo"
  if [ ! -d "$path" ]; then
    echo "⚠️  $repo — not found"
    continue
  fi

  if ! git -C "$path" rev-parse --is-inside-work-tree &>/dev/null; then
    echo "⚠️  $repo — not a git repo"
    continue
  fi

  branch=$(git -C "$path" branch --show-current 2>/dev/null)
  branch="${branch:-(detached)}"
  dirty=$(git -C "$path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  last_tag=$(git -C "$path" describe --tags --abbrev=0 2>/dev/null || echo "(none)")

  if [ "$dirty" -eq 0 ]; then
    clean_icon="✅"
  else
    clean_icon="⚠️ ($dirty files)"
  fi

  echo "$repo"
  echo "  Branch:   $branch"
  echo "  Clean:    $clean_icon"
  echo "  Last tag: $last_tag"
  echo ""
done
