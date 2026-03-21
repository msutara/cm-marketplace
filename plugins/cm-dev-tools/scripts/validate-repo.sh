#!/usr/bin/env bash
# validate-repo.sh — Build + test + lint a single CM repo
# Usage: ./validate-repo.sh <repo-path> [--skip-lint] [--skip-markdown]
set -euo pipefail

REPO_PATH="${1:?Usage: validate-repo.sh <repo-path> [--skip-lint] [--skip-markdown]}"
if [ ! -d "$REPO_PATH" ]; then
  echo "Error: directory not found: $REPO_PATH" >&2
  exit 1
fi

if ! command -v go &>/dev/null; then
  echo "Error: go is required but not installed. See: https://go.dev/dl/" >&2
  exit 1
fi

SKIP_LINT=false
SKIP_MARKDOWN=false
for arg in "${@:2}"; do
  case "$arg" in
    --skip-lint) SKIP_LINT=true ;;
    --skip-markdown) SKIP_MARKDOWN=true ;;
    *) echo "Error: unknown option: $arg" >&2; exit 1 ;;
  esac
done

REPO_NAME="$(basename "$REPO_PATH")"
OVERALL=0
_tmp_files=()
# shellcheck disable=SC2317,SC2329
cleanup() { if [[ ${#_tmp_files[@]} -gt 0 ]]; then rm -f "${_tmp_files[@]}"; fi; }
trap cleanup EXIT INT TERM

run_step() {
  local name="$1"; shift
  local start end duration
  local tmpfile
  tmpfile=$(mktemp "${TMPDIR:-/tmp}/cm-${name}-XXXXXX"); _tmp_files+=("$tmpfile")
  start=$(date +%s)
  if "$@" > "$tmpfile" 2>&1; then
    end=$(date +%s); duration=$(( end - start ))
    echo "  ✅ $name (${duration}s)"
  else
    end=$(date +%s); duration=$(( end - start ))
    echo "  ❌ $name (${duration}s)"
    head -10 "$tmpfile" | sed 's/^/     /'
    OVERALL=1
  fi
}

cd "$REPO_PATH"

echo "--- $REPO_NAME ---"
run_step build go build ./...
run_step test go test ./...

if [ "$SKIP_LINT" = false ]; then
  if command -v golangci-lint &>/dev/null; then
    run_step lint golangci-lint run
  else
    echo "  ⚠️  golangci-lint not found — install: https://golangci-lint.run/welcome/install/"
  fi
fi

if [ "$SKIP_MARKDOWN" = false ]; then
  if command -v markdownlint-cli2 &>/dev/null; then
    run_step markdownlint markdownlint-cli2 "**/*.md" "#node_modules"
  else
    echo "  ⚠️  markdownlint-cli2 not found — install: npm i -g markdownlint-cli2"
  fi
fi

if [ "$OVERALL" -eq 0 ]; then
  echo "✅ $REPO_NAME"
else
  echo "❌ $REPO_NAME"
fi
exit "$OVERALL"
