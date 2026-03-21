#!/usr/bin/env bash
# validate-all.sh — Validate all CM repos defined in the project manifest
# Usage: ./validate-all.sh [--skip-lint] [--skip-markdown]
# Intentionally omit -e: script must continue through repo failures to accumulate results
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/load-project.sh
source "$SCRIPT_DIR/lib/load-project.sh" || exit 1
ALL_PASSED=0
SUMMARIES=()

for repo in "${REPOS[@]}"; do
  repo_path="$REPO_BASE/$repo"
  if [ ! -d "$repo_path" ]; then
    echo "⚠️  $repo — directory not found at $repo_path"
    SUMMARIES+=("❌ $repo — directory not found")
    ALL_PASSED=1
    continue
  fi
  if "$SCRIPT_DIR/validate-repo.sh" "$repo_path" "$@"; then
    SUMMARIES+=("✅ $repo")
  else
    SUMMARIES+=("❌ $repo")
    ALL_PASSED=1
  fi
  echo ""
done

echo "=== SUMMARY ==="
for s in "${SUMMARIES[@]}"; do
  echo "$s"
done

if [ "$ALL_PASSED" -eq 0 ]; then
  printf "\n✅ Overall: ALL PASSED\n"
else
  printf "\n❌ Overall: FAILURES DETECTED\n"
fi
exit "$ALL_PASSED"
