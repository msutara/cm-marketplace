#!/usr/bin/env bash
# sync-deps.sh — Bump a go.mod dependency across downstream CM repos
# Usage: ./sync-deps.sh <source-module> <version>
# Example: ./sync-deps.sh github.com/msutara/config-manager-core v0.5.0
set -euo pipefail

if ! command -v go &>/dev/null; then
  echo "Error: go is required but not installed. See: https://go.dev/dl/" >&2
  exit 1
fi

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
_tmp_files=()
# shellcheck disable=SC2317,SC2329
cleanup() { if [[ ${#_tmp_files[@]} -gt 0 ]]; then rm -f "${_tmp_files[@]}"; fi; }
trap cleanup EXIT INT TERM

for repo in "${ALL_REPOS[@]}"; do
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
    continue
  fi

  echo "Updating $repo..."
  pushd "$path" > /dev/null

  tmp_err=$(mktemp "${TMPDIR:-/tmp}/cm-sync-deps.XXXXXX"); _tmp_files+=("$tmp_err")
  if ! go get "${SOURCE_MODULE}@${VERSION}" 2>"$tmp_err"; then
    ERRORS+=("$repo: go get failed: $(cat "$tmp_err")")
    popd > /dev/null
    continue
  fi

  tmp_err=$(mktemp "${TMPDIR:-/tmp}/cm-sync-deps.XXXXXX"); _tmp_files+=("$tmp_err")
  if ! go mod tidy 2>"$tmp_err"; then
    ERRORS+=("$repo: go mod tidy failed: $(cat "$tmp_err")")
    popd > /dev/null
    continue
  fi

  echo "  ✅ $repo updated to ${SOURCE_MODULE}@${VERSION}"
  UPDATED+=("$repo")
  popd > /dev/null
done

echo ""
echo "=== Summary ==="
if [ ${#UPDATED[@]} -gt 0 ]; then
  echo "Updated: ${UPDATED[*]}"
else
  echo "Updated: none"
fi
if [ ${#ERRORS[@]} -gt 0 ]; then
  echo "Errors:"
  for err in "${ERRORS[@]}"; do
    echo "  ❌ $err"
  done
  exit 1
fi
