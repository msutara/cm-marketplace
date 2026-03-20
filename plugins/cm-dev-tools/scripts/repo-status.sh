#!/usr/bin/env bash
# repo-status.sh — Git status, branch, and last tag for CM repos
# Usage: ./repo-status.sh [repo-name]
set -uo pipefail

REPO_BASE="${CM_REPO_BASE:-$HOME/repo}"
REPOS=(
  config-manager-core
  cm-plugin-network
  cm-plugin-update
  config-manager-tui
  config-manager-web
)

if [ "${1:-}" ]; then
  REPOS=("$1")
fi

for repo in "${REPOS[@]}"; do
  path="$REPO_BASE/$repo"
  if [ ! -d "$path" ]; then
    echo "⚠️  $repo — not found"
    continue
  fi

  branch=$(git -C "$path" branch --show-current 2>/dev/null || echo "(detached)")
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
