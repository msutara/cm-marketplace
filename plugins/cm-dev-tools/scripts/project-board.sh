#!/usr/bin/env bash
# project-board.sh — Add/update items on the CM GitHub project board
# Usage: ./project-board.sh --url <github-url> [--status <Backlog|InProgress|Review|Done>]
#        ./project-board.sh --item-id <id> --status <status>
set -euo pipefail

PROJECT_ID="PVT_kwHOAgHix84BPSxN"
STATUS_FIELD_ID="PVTSSF_lAHOAgHix84BPSxNzg9vkrk"
declare -A STATUS_OPTIONS=(
  [Backlog]="f75ad846"
  [InProgress]="47fc9ee4"
  [Review]="e70217cf"
  [Done]="98236657"
)

URL=""
STATUS=""
ITEM_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) URL="$2"; shift 2 ;;
    --status) STATUS="$2"; shift 2 ;;
    --item-id) ITEM_ID="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Add item if URL provided
if [ -n "$URL" ]; then
  echo "Adding $URL to project board..."
  if gh project item-add 1 --owner msutara --url "$URL" 2>/dev/null; then
    echo "  ✅ Added to project"
  else
    echo "  ⚠️  Failed to add (may already exist)"
  fi
fi

# Update status if requested
if [ -n "$STATUS" ]; then
  option_id="${STATUS_OPTIONS[$STATUS]:-}"
  if [ -z "$option_id" ]; then
    echo "Error: Invalid status '$STATUS'. Use: Backlog, InProgress, Review, Done" >&2
    exit 1
  fi

  # Find item ID from URL if not provided
  if [ -z "$ITEM_ID" ] && [ -n "$URL" ]; then
    ITEM_ID=$(gh project item-list 1 --owner msutara --format json 2>/dev/null \
      | jq -r --arg url "$URL" '.items[] | select(.content.url == $url) | .id' 2>/dev/null || true)
  fi

  if [ -n "$ITEM_ID" ]; then
    mutation="mutation { updateProjectV2ItemFieldValue(input: {projectId: \"$PROJECT_ID\", itemId: \"$ITEM_ID\", fieldId: \"$STATUS_FIELD_ID\", value: {singleSelectOptionId: \"$option_id\"}}) { projectV2Item { id } } }"
    if gh api graphql -f query="$mutation" >/dev/null 2>&1; then
      echo "  ✅ Status updated to $STATUS"
    else
      echo "  ❌ Failed to update status"
      exit 1
    fi
  else
    echo "  ⚠️  Could not find item ID — add item first or provide --item-id"
  fi
fi
