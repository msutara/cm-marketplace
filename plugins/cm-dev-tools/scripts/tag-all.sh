#!/usr/bin/env bash
# tag-all.sh — Tag all 5 CM repos in dependency order
# Usage: ./tag-all.sh <version> [--dry-run]
set -euo pipefail

VERSION="${1:?Usage: tag-all.sh <version> [--dry-run]}"
DRY_RUN=false
[ "${2:-}" = "--dry-run" ] && DRY_RUN=true

if ! [[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: Version must be semver format: v{MAJOR}.{MINOR}.{PATCH}" >&2
  exit 1
fi

REPO_BASE="${CM_REPO_BASE:-$HOME/repo}"
DEP_ORDER=(
  config-manager-core
  cm-plugin-network
  cm-plugin-update
  config-manager-tui
  config-manager-web
)

for repo in "${DEP_ORDER[@]}"; do
  path="$REPO_BASE/$repo"
  if [ ! -d "$path" ]; then
    echo "Error: $repo not found at $path" >&2
    exit 1
  fi

  # Verify clean working tree
  if [ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]; then
    echo "Error: $repo has uncommitted changes — aborting" >&2
    exit 1
  fi

  # Verify on main branch
  branch=$(git -C "$path" branch --show-current 2>/dev/null)
  if [ "$branch" != "main" ]; then
    echo "Error: $repo is on branch '$branch', not 'main' — aborting" >&2
    exit 1
  fi

  if [ "$DRY_RUN" = true ]; then
    echo "[DRY RUN] Would tag $repo at $VERSION"
  else
    echo "Tagging $repo at $VERSION..."
    git -C "$path" tag "$VERSION"
    git -C "$path" push origin "$VERSION"
    echo "  ✅ $repo tagged and pushed $VERSION"
  fi
done

echo -e "\n✅ All repos tagged at $VERSION"
