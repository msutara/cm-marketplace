#!/usr/bin/env bash
# validate-all.sh — Validate all CM repos defined in the project manifest
# Usage: ./validate-all.sh [--skip-lint] [--skip-markdown] [--json]
# Intentionally omit -e: script must continue through repo failures to accumulate results
set -uo pipefail

JSON_OUTPUT=false
PASS_ARGS=()
for arg in "$@"; do
  if [[ "$arg" == "--json" ]]; then
    JSON_OUTPUT=true
  else
    PASS_ARGS+=("$arg")
  fi
done

if $JSON_OUTPUT && ! command -v jq &>/dev/null; then
  printf '{"ok":false,"tool":"validate-all","data":null,"error":"jq is required for --json output but is not installed"}\n'
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
logf() {
  if $JSON_OUTPUT; then
    # shellcheck disable=SC2059
    printf "$@" >&2
  else
    # shellcheck disable=SC2059
    printf "$@"
  fi
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/load-project.sh
if ! source "$SCRIPT_DIR/lib/load-project.sh"; then
  echo "Error: failed to load project manifest." >&2
  if $JSON_OUTPUT; then
    printf '{"ok":false,"tool":"validate-all","data":null,"error":"failed to load project manifest."}\n'
  fi
  exit 1
fi
ALL_PASSED=0
SUMMARIES=()

# JSON accumulators
_json_repo_names=()
_json_repo_pass=()
_json_repo_details=()
_passed_count=0
_failed_count=0

for repo in "${REPOS[@]}"; do
  repo_path="$REPO_BASE/$repo"
  if [ ! -d "$repo_path" ]; then
    log "⚠️  $repo — directory not found at $repo_path"
    SUMMARIES+=("❌ $repo — directory not found")
    ALL_PASSED=1
    _json_repo_names+=("$repo")
    _json_repo_pass+=(false)
    _json_repo_details+=('null')
    (( _failed_count++ )) || true
    continue
  fi
  if $JSON_OUTPUT; then
    # Run validate-repo.sh with --json; capture stdout (JSON) separately from stderr (logs)
    _sub_json=$("$SCRIPT_DIR/validate-repo.sh" "$repo_path" "${PASS_ARGS[@]+"${PASS_ARGS[@]}"}" --json) && _sub_rc=0 || _sub_rc=$?
    if [ "$_sub_rc" -eq 0 ]; then
      SUMMARIES+=("✅ $repo")
      _json_repo_names+=("$repo")
      _json_repo_pass+=(true)
      _json_repo_details+=("${_sub_json:-null}")
      (( _passed_count++ )) || true
    else
      SUMMARIES+=("❌ $repo")
      ALL_PASSED=1
      _json_repo_names+=("$repo")
      _json_repo_pass+=(false)
      _json_repo_details+=("${_sub_json:-null}")
      (( _failed_count++ )) || true
    fi
  else
    if "$SCRIPT_DIR/validate-repo.sh" "$repo_path" "${PASS_ARGS[@]+"${PASS_ARGS[@]}"}"; then
      SUMMARIES+=("✅ $repo")
      _json_repo_names+=("$repo")
      _json_repo_pass+=(true)
      _json_repo_details+=('null')
      (( _passed_count++ )) || true
    else
      SUMMARIES+=("❌ $repo")
      ALL_PASSED=1
      _json_repo_names+=("$repo")
      _json_repo_pass+=(false)
      _json_repo_details+=('null')
      (( _failed_count++ )) || true
    fi
  fi
  log ""
done

log "=== SUMMARY ==="
for s in "${SUMMARIES[@]}"; do
  log "$s"
done

if [ "$ALL_PASSED" -eq 0 ]; then
  logf "\n✅ Overall: ALL PASSED\n"
else
  logf "\n❌ Overall: FAILURES DETECTED\n"
fi

if $JSON_OUTPUT; then
  _total=$(( _passed_count + _failed_count ))
  _repos_json="[]"
  for i in "${!_json_repo_names[@]}"; do
    _repos_json=$(printf '%s' "$_repos_json" | jq -c \
      --arg name "${_json_repo_names[$i]}" \
      --argjson pass "${_json_repo_pass[$i]}" \
      --argjson detail "${_json_repo_details[$i]}" \
      '. + [{name: $name, pass: $pass, detail: $detail}]')
  done
  _error_msg="null"
  if [ "$ALL_PASSED" -ne 0 ]; then
    _error_msg="\"$_failed_count of $_total repos failed validation\""
  fi
  jq -nc \
    --argjson ok "$([ "$ALL_PASSED" -eq 0 ] && echo true || echo false)" \
    --argjson repos "$_repos_json" \
    --argjson passed "$_passed_count" \
    --argjson failed "$_failed_count" \
    --argjson total "$_total" \
    --argjson error "$_error_msg" \
    '{ok: $ok, tool: "validate-all", data: {repos: $repos, passed: $passed, failed: $failed, total: $total}, error: $error}'
fi
exit "$ALL_PASSED"
