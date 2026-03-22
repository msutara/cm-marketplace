#!/usr/bin/env bash
# validate-repo.sh — Build + test + lint a single CM repo
# Usage: ./validate-repo.sh <repo-path> [--skip-lint] [--skip-markdown] [--json]
set -euo pipefail

# Parse flags early (before any validation) so JSON_OUTPUT is available for all error paths
JSON_OUTPUT=false
SKIP_LINT=false
SKIP_MARKDOWN=false
_positional_args=()
for arg in "$@"; do
  case "$arg" in
    --json) JSON_OUTPUT=true ;;
    --skip-lint) SKIP_LINT=true ;;
    --skip-markdown) SKIP_MARKDOWN=true ;;
    --*)
      echo "Error: unknown option: $arg" >&2
      if $JSON_OUTPUT; then
        jq -nc --arg error "unknown option: $arg" '{ok: false, tool: "validate-repo", data: null, error: $error}'
      fi
      exit 1 ;;
    *) _positional_args+=("$arg") ;;
  esac
done

REPO_PATH="${_positional_args[0]:-}"
if [ -z "$REPO_PATH" ]; then
  echo "Usage: validate-repo.sh <repo-path> [--skip-lint] [--skip-markdown] [--json]" >&2
  if $JSON_OUTPUT; then
    jq -nc '{ok: false, tool: "validate-repo", data: null, error: "missing required argument: repo-path"}'
  fi
  exit 1
fi

if [ ! -d "$REPO_PATH" ]; then
  echo "Error: directory not found: $REPO_PATH" >&2
  if $JSON_OUTPUT; then
    jq -nc --arg error "directory not found: $REPO_PATH" '{ok: false, tool: "validate-repo", data: null, error: $error}'
  fi
  exit 1
fi

if ! command -v go &>/dev/null; then
  echo "Error: go is required but not installed. See: https://go.dev/dl/" >&2
  if $JSON_OUTPUT; then
    jq -nc '{ok: false, tool: "validate-repo", data: null, error: "go is required but not installed."}'
  fi
  exit 1
fi

# Helper: log to stderr when in JSON mode, stdout otherwise
log() {
  if $JSON_OUTPUT; then
    echo "$@" >&2
  else
    echo "$@"
  fi
}

REPO_NAME="$(basename "$REPO_PATH")"
OVERALL=0
_tmp_files=()
# shellcheck disable=SC2317,SC2329
cleanup() { if [[ ${#_tmp_files[@]} -gt 0 ]]; then rm -f "${_tmp_files[@]}"; fi; }
trap cleanup EXIT INT TERM

# JSON step tracking: parallel arrays
_json_step_names=()
_json_step_pass=()
_json_step_duration=()
_json_step_skipped=()

run_step() {
  local name="$1"; shift
  local start end duration
  local tmpfile
  tmpfile=$(mktemp "${TMPDIR:-/tmp}/cm-${name}-XXXXXX"); _tmp_files+=("$tmpfile")
  start=$(date +%s.%N 2>/dev/null || date +%s)
  if "$@" > "$tmpfile" 2>&1; then
    end=$(date +%s.%N 2>/dev/null || date +%s)
    duration=$(printf '%.1f' "$(echo "$end - $start" | bc 2>/dev/null || echo "$(( ${end%%.*} - ${start%%.*} ))")")
    log "  ✅ $name (${duration}s)"
    _json_step_names+=("$name")
    _json_step_pass+=(true)
    _json_step_duration+=("$duration")
    _json_step_skipped+=(false)
  else
    end=$(date +%s.%N 2>/dev/null || date +%s)
    duration=$(printf '%.1f' "$(echo "$end - $start" | bc 2>/dev/null || echo "$(( ${end%%.*} - ${start%%.*} ))")")
    log "  ❌ $name (${duration}s)"
    if $JSON_OUTPUT; then
      head -10 "$tmpfile" | sed 's/^/     /' >&2
    else
      head -10 "$tmpfile" | sed 's/^/     /'
    fi
    _json_step_names+=("$name")
    _json_step_pass+=(false)
    _json_step_duration+=("$duration")
    _json_step_skipped+=(false)
    OVERALL=1
  fi
}

cd "$REPO_PATH" || {
  echo "Error: failed to cd into $REPO_PATH" >&2
  if $JSON_OUTPUT; then
    jq -nc --arg error "failed to cd into $REPO_PATH" '{ok: false, tool: "validate-repo", data: null, error: $error}'
  fi
  exit 1
}

log "--- $REPO_NAME ---"
run_step build go build ./...
run_step test go test ./...

if [ "$SKIP_LINT" = false ]; then
  if command -v golangci-lint &>/dev/null; then
    run_step lint golangci-lint run
  else
    log "  ⚠️  golangci-lint not found — install: https://golangci-lint.run/welcome/install/"
    _json_step_names+=("lint")
    _json_step_pass+=(true)
    _json_step_duration+=("0.0")
    _json_step_skipped+=(true)
  fi
else
  _json_step_names+=("lint")
  _json_step_pass+=(true)
  _json_step_duration+=("0.0")
  _json_step_skipped+=(true)
fi

if [ "$SKIP_MARKDOWN" = false ]; then
  if command -v markdownlint-cli2 &>/dev/null; then
    run_step markdownlint markdownlint-cli2 "**/*.md" "#node_modules"
  else
    log "  ⚠️  markdownlint-cli2 not found — install: npm i -g markdownlint-cli2"
    _json_step_names+=("markdownlint")
    _json_step_pass+=(true)
    _json_step_duration+=("0.0")
    _json_step_skipped+=(true)
  fi
else
  _json_step_names+=("markdownlint")
  _json_step_pass+=(true)
  _json_step_duration+=("0.0")
  _json_step_skipped+=(true)
fi

if [ "$OVERALL" -eq 0 ]; then
  log "✅ $REPO_NAME"
else
  log "❌ $REPO_NAME"
fi

if $JSON_OUTPUT; then
  # Build per-step JSON objects and assemble the data
  _data_json="{}"
  _error_msg="null"
  _failed_steps=()
  for i in "${!_json_step_names[@]}"; do
    _sname="${_json_step_names[$i]}"
    _spass="${_json_step_pass[$i]}"
    _sdur="${_json_step_duration[$i]}"
    _sskip="${_json_step_skipped[$i]}"
    _step_json=$(jq -nc \
      --argjson pass "$_spass" \
      --argjson duration "$_sdur" \
      --argjson skipped "$_sskip" \
      '{pass: $pass, duration: $duration, skipped: $skipped}')
    _data_json=$(printf '%s' "$_data_json" | jq -c --arg k "$_sname" --argjson v "$_step_json" '. + {($k): $v}')
    if [ "$_spass" = "false" ]; then
      _failed_steps+=("$_sname")
    fi
  done
  if [ "$OVERALL" -ne 0 ]; then
    _error_msg="\"$REPO_NAME: ${_failed_steps[*]} failed\""
  fi
  jq -nc \
    --argjson ok "$([ "$OVERALL" -eq 0 ] && echo true || echo false)" \
    --arg repo "$REPO_NAME" \
    --argjson data "$_data_json" \
    --argjson error "$_error_msg" \
    '{ok: $ok, tool: "validate-repo", data: ({repo: $repo} + $data), error: $error}'
fi
exit "$OVERALL"
