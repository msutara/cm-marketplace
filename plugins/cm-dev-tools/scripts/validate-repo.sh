#!/usr/bin/env bash
# validate-repo.sh — Build + test + lint a single CM repo
# Usage: ./validate-repo.sh <repo-path> [--skip-lint] [--skip-markdown]
set -euo pipefail

REPO_PATH="${1:?Usage: validate-repo.sh <repo-path> [--skip-lint] [--skip-markdown]}"
SKIP_LINT=false
SKIP_MARKDOWN=false
for arg in "${@:2}"; do
  case "$arg" in
    --skip-lint) SKIP_LINT=true ;;
    --skip-markdown) SKIP_MARKDOWN=true ;;
  esac
done

REPO_NAME="$(basename "$REPO_PATH")"
OVERALL=0

run_step() {
  local name="$1"; shift
  local start end duration
  start=$(date +%s)
  if "$@" > /tmp/cm-"$name"-out.txt 2>&1; then
    end=$(date +%s); duration=$(( end - start ))
    echo "  ✅ $name (${duration}s)"
  else
    end=$(date +%s); duration=$(( end - start ))
    echo "  ❌ $name (${duration}s)"
    head -10 /tmp/cm-"$name"-out.txt | sed 's/^/     /'
    OVERALL=1
  fi
}

cd "$REPO_PATH"

echo "--- $REPO_NAME ---"
run_step build go build ./...
run_step test go test ./...

if [ "$SKIP_LINT" = false ]; then
  run_step lint golangci-lint run
fi

if [ "$SKIP_MARKDOWN" = false ] && command -v markdownlint-cli2 &>/dev/null; then
  run_step markdownlint markdownlint-cli2 "**/*.md" "#node_modules"
fi

if [ "$OVERALL" -eq 0 ]; then
  echo "✅ $REPO_NAME"
else
  echo "❌ $REPO_NAME"
fi
exit "$OVERALL"
