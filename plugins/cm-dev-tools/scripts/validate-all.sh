#!/usr/bin/env bash
# validate-all.sh — Validate all 5 CM repos in sequence
# Usage: ./validate-all.sh [--skip-lint] [--skip-markdown]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_BASE="${CM_REPO_BASE:-$HOME/repo}"
REPOS=(
  config-manager-core
  cm-plugin-network
  cm-plugin-update
  config-manager-tui
  config-manager-web
)
PASS_ARGS=("${@}")
ALL_PASSED=0
SUMMARIES=()

for repo in "${REPOS[@]}"; do
  repo_path="$REPO_BASE/$repo"
  if [ ! -d "$repo_path" ]; then
    echo "⚠️  $repo — directory not found at $repo_path"
    continue
  fi
  if "$SCRIPT_DIR/validate-repo.sh" "$repo_path" "${PASS_ARGS[@]+"${PASS_ARGS[@]}"}"; then
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
  echo -e "\n✅ Overall: ALL PASSED"
else
  echo -e "\n❌ Overall: FAILURES DETECTED"
fi
exit "$ALL_PASSED"
