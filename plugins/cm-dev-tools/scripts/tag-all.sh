#!/usr/bin/env bash
# tag-all.sh — Tag all 5 CM repos in dependency order
# Usage: ./tag-all.sh <version> [--dry-run]
set -euo pipefail

if ! command -v git &>/dev/null; then
  echo "Error: git is required but not installed." >&2
  exit 1
fi

VERSION="${1:?Usage: tag-all.sh <version> [--dry-run]}"
DRY_RUN=false
for arg in "${@:2}"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    *) echo "Error: unknown option: $arg" >&2; exit 1 ;;
  esac
done

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

  # Verify on main branch (empty means detached HEAD)
  branch=$(git -C "$path" branch --show-current 2>/dev/null)
  if [ -z "$branch" ]; then
    echo "Error: $repo is in detached HEAD state — aborting" >&2
    exit 1
  fi
  if [ "$branch" != "main" ]; then
    echo "Error: $repo is on branch '$branch', not 'main' — aborting" >&2
    exit 1
  fi

  # Skip if already tagged at this version (check remote too)
  git -C "$path" fetch --tags --quiet 2>/dev/null || true
  if git -C "$path" tag -l "$VERSION" | grep -q .; then
    echo "  ⏭️  $repo already tagged at $VERSION — skipping"
    continue
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

if [ "$DRY_RUN" = true ]; then
  printf "\n✅ [DRY RUN] All repos would be tagged at %s\n" "$VERSION"
else
  printf "\n✅ All repos tagged at %s\n" "$VERSION"
fi
