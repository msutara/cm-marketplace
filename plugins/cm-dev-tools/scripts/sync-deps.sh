#!/usr/bin/env bash
# sync-deps.sh — Bump a go.mod dependency across downstream CM repos
# Usage: ./sync-deps.sh <source-module> <version>
# Example: ./sync-deps.sh github.com/msutara/config-manager-core v0.5.0
set -euo pipefail

SOURCE_MODULE="${1:?Usage: sync-deps.sh <source-module> <version>}"
VERSION="${2:?Usage: sync-deps.sh <source-module> <version>}"

REPO_BASE="${CM_REPO_BASE:-$HOME/repo}"
ALL_REPOS=(
  config-manager-core
  cm-plugin-network
  cm-plugin-update
  config-manager-tui
  config-manager-web
)

UPDATED=()
ERRORS=()

for repo in "${ALL_REPOS[@]}"; do
  path="$REPO_BASE/$repo"
  gomod="$path/go.mod"

  [ ! -f "$gomod" ] && continue

  # Skip if this repo doesn't import the source module
  if ! grep -q "$SOURCE_MODULE" "$gomod"; then
    continue
  fi

  # Skip self (the module that was just updated)
  if head -1 "$gomod" | grep -q "$SOURCE_MODULE"; then
    continue
  fi

  echo "Updating $repo..."
  cd "$path"

  if ! go get "${SOURCE_MODULE}@${VERSION}" 2>/tmp/cm-sync-err.txt; then
    ERRORS+=("$repo: go get failed: $(cat /tmp/cm-sync-err.txt)")
    continue
  fi

  if ! go mod tidy 2>/tmp/cm-sync-err.txt; then
    ERRORS+=("$repo: go mod tidy failed: $(cat /tmp/cm-sync-err.txt)")
    continue
  fi

  echo "  ✅ $repo updated to ${SOURCE_MODULE}@${VERSION}"
  UPDATED+=("$repo")
done

echo ""
echo "=== Summary ==="
echo "Updated: ${UPDATED[*]:-none}"
if [ ${#ERRORS[@]} -gt 0 ]; then
  echo "Errors:"
  for err in "${ERRORS[@]}"; do
    echo "  ❌ $err"
  done
  exit 1
fi
