#!/usr/bin/env bash
# sync-deps.sh — Bump a go.mod dependency across downstream CM repos
# Usage: ./sync-deps.sh <source-module> <version>
# Example: ./sync-deps.sh github.com/{OWNER}/config-manager-core v0.5.0
set -euo pipefail

if ! command -v go &>/dev/null; then
  echo "Error: go is required but not installed. See: https://go.dev/dl/" >&2
  exit 1
fi

SOURCE_MODULE="${1:?Usage: sync-deps.sh <source-module> <version>}"
VERSION="${2:?Usage: sync-deps.sh <source-module> <version>}"

# Validate inputs to prevent command injection
if [[ ! "$SOURCE_MODULE" =~ ^[a-zA-Z0-9][a-zA-Z0-9._/-]*$ ]] || [[ "$SOURCE_MODULE" == *..* ]]; then
  echo "Error: Invalid source module format: $SOURCE_MODULE" >&2
  exit 1
fi
# Allow semver, pseudo-versions (v0.0.0-...-hash), and build metadata
if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+[a-zA-Z0-9._+-]*$ ]]; then
  echo "Error: Invalid version format: $VERSION (expected vX.Y.Z with optional pre-release)" >&2
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
    continue
  fi

  echo "Updating $repo..."
  pushd "$path" > /dev/null

  tmp_err=$(mktemp "${TMPDIR:-/tmp}/cm-sync-deps.XXXXXX"); _tmp_files+=("$tmp_err")
  if ! go get "${SOURCE_MODULE}@${VERSION}" 2>"$tmp_err"; then
    ERRORS+=("$repo: go get failed: $(<"$tmp_err")")
    popd > /dev/null
    continue
  fi

  tmp_err=$(mktemp "${TMPDIR:-/tmp}/cm-sync-deps.XXXXXX"); _tmp_files+=("$tmp_err")
  if ! go mod tidy 2>"$tmp_err"; then
    ERRORS+=("$repo: go mod tidy failed: $(<"$tmp_err")")
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
  echo "Errors:" >&2
  for err in "${ERRORS[@]}"; do
    echo "  ❌ $err" >&2
  done
  exit 1
fi
