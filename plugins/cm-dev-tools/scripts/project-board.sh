#!/usr/bin/env bash
# project-board.sh — Add/update items on the CM GitHub project board
# Usage: ./project-board.sh --url <github-url> [--status <Backlog|InProgress|Review|Done>]
#        ./project-board.sh --item-id <id> --status <status>
set -euo pipefail

_cleanup_files=()
# shellcheck disable=SC2317,SC2329
cleanup() { if [[ ${#_cleanup_files[@]} -gt 0 ]]; then rm -f "${_cleanup_files[@]}"; fi; }
trap cleanup EXIT INT TERM

# Verify gh CLI is available
if ! command -v gh &>/dev/null; then
  echo "Error: gh (GitHub CLI) is required but not installed. See: https://cli.github.com/" >&2
  exit 1
fi

# Requires bash 4+ for associative arrays (checked in load-project.sh)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib/load-project.sh
source "$SCRIPT_DIR/lib/load-project.sh"

# project-board.sh requires project_board config in the manifest
if [[ -z "$PROJECT_NUMBER" || "$PROJECT_NUMBER" == "null" || \
      -z "$PROJECT_ID" || "$PROJECT_ID" == "null" || \
      -z "$STATUS_FIELD_ID" || "$STATUS_FIELD_ID" == "null" ]]; then
  echo "Error: project_board config missing or incomplete in manifest." >&2
  echo "Run init-project.sh to configure project board settings." >&2
  exit 1
fi

URL=""
STATUS=""
ITEM_ID=""

usage() {
  echo "Usage:" >&2
  echo "  $(basename "$0") --url <github-url> [--status <Backlog|InProgress|Review|Done>]" >&2
  echo "  $(basename "$0") --item-id <id> --status <status>" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "Error: --url requires a non-empty value." >&2; usage; exit 1
      fi
      URL="$2"; shift 2 ;;
    --status)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "Error: --status requires a non-empty value." >&2; usage; exit 1
      fi
      STATUS="$2"; shift 2 ;;
    --item-id)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "Error: --item-id requires a non-empty value." >&2; usage; exit 1
      fi
      ITEM_ID="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$URL" && -z "$ITEM_ID" && -z "$STATUS" ]]; then
  echo "Error: at least one of --url, --item-id, or --status must be provided." >&2
  usage
  exit 1
fi

if [[ -n "$STATUS" && -z "$URL" && -z "$ITEM_ID" ]]; then
  echo "Error: --status requires either --url or --item-id to identify the item." >&2
  usage
  exit 1
fi

# Add item if URL provided
ADDED_ITEM_ID=""
if [ -n "$URL" ]; then
  echo "Adding $URL to project board..."
  _gh_add_err=$(mktemp "${TMPDIR:-/tmp}/cm-project-board.XXXXXX"); _cleanup_files+=("$_gh_add_err")
  if add_result=$(gh project item-add "$PROJECT_NUMBER" --owner "$OWNER" --url "$URL" --format json 2>"$_gh_add_err"); then
    if ! ADDED_ITEM_ID=$(echo "$add_result" | jq -er '.id // empty' 2>/dev/null); then
      echo "  ❌ Failed to parse project item ID from gh output." >&2
      echo "      Raw output: $add_result" >&2
      exit 1
    fi
    if [ -z "$ADDED_ITEM_ID" ] || [ "$ADDED_ITEM_ID" = "null" ]; then
      echo "  ❌ Project item ID is missing or null in gh output." >&2
      echo "      Raw output: $add_result" >&2
      exit 1
    fi
    echo "  ✅ Added to project (item: ${ADDED_ITEM_ID:-unknown})"
  else
    # Item may already exist — fall through to item-list lookup for status update
    echo "  ⚠️  item-add failed (may already exist): $(cat "$_gh_add_err")"
  fi
fi

# Update status if requested
if [ -n "$STATUS" ]; then
  option_id="${STATUS_OPTIONS[$STATUS]:-}"
  if [ -z "$option_id" ]; then
    echo "Error: Invalid status '$STATUS'. Available: ${!STATUS_OPTIONS[*]}" >&2
    exit 1
  fi

  # Use item ID from add result, explicit param, or list lookup
  if [ -z "$ITEM_ID" ] && [ -n "$ADDED_ITEM_ID" ]; then
    ITEM_ID="$ADDED_ITEM_ID"
  fi
  if [ -z "$ITEM_ID" ] && [ -n "$URL" ]; then
    ITEM_ID=$(gh project item-list "$PROJECT_NUMBER" --owner "$OWNER" --limit 500 --format json 2>/dev/null \
      | jq -r --arg url "$URL" '.items[] | select(.content.url == $url) | .id' 2>/dev/null || true)
  fi

  if [ -n "$ITEM_ID" ]; then
    mutation="mutation { updateProjectV2ItemFieldValue(input: {projectId: \"$PROJECT_ID\", itemId: \"$ITEM_ID\", fieldId: \"$STATUS_FIELD_ID\", value: {singleSelectOptionId: \"$option_id\"}}) { projectV2Item { id } } }"
    _gql_err=$(mktemp "${TMPDIR:-/tmp}/cm-gql-err.XXXXXX"); _cleanup_files+=("$_gql_err")
    if output=$(gh api graphql -f query="$mutation" 2>"$_gql_err"); then
      # GraphQL can return 200 with errors in the body
      if echo "$output" | jq -e '.errors' &>/dev/null; then
        echo "  ❌ GraphQL mutation returned errors" >&2
        echo "$output" | jq -r '.errors[].message' >&2
        exit 1
      fi
      echo "  ✅ Status updated to $STATUS"
    else
      echo "  ❌ Failed to update status" >&2
      echo "  $(cat "$_gql_err")" >&2
      exit 1
    fi
  else
    echo "  ⚠️  Could not find item ID — add item first or provide --item-id" >&2
    exit 1
  fi
fi
