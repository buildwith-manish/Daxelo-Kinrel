#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# DAXELO KINREL — Tag Release Script
#
# Reads version from pubspec.yaml, creates a git tag, and pushes to origin.
#
# Usage:
#   ./scripts/tag_release.sh
#   ./scripts/tag_release.sh --dry-run    # Show what would happen without tagging
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Locate project root ─────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

# ── Parse flags ──────────────────────────────────────────────────────────────
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

# ── Read version from pubspec.yaml ──────────────────────────────────────────
PUBSPEC="$PROJECT_DIR/pubspec.yaml"

if [ ! -f "$PUBSPEC" ]; then
  echo -e "${RED}❌ pubspec.yaml not found at $PUBSPEC${NC}" >&2
  exit 1
fi

VERSION_LINE=$(grep -E "^version:" "$PUBSPEC" | head -1)

if [ -z "$VERSION_LINE" ]; then
  echo -e "${RED}❌ No 'version:' field found in pubspec.yaml${NC}" >&2
  exit 1
fi

# Extract version string (e.g., "1.0.0+1" → full version, "1.0.0" → semver)
FULL_VERSION=$(echo "$VERSION_LINE" | sed -E 's/^version:[[:space:]]*//' | tr -d '[:space:]')
SEMVER_VERSION=$(echo "$FULL_VERSION" | sed -E 's/\+.*$//')
TAG="v${SEMVER_VERSION}"

# ── Validate version ────────────────────────────────────────────────────────
if [ -z "$SEMVER_VERSION" ]; then
  echo -e "${RED}❌ Could not parse version from pubspec.yaml${NC}" >&2
  exit 1
fi

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║        DAXELO KINREL — Tag Release                         ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo -e "  pubspec.yaml version : ${BOLD}${FULL_VERSION}${NC}"
echo -e "  Tag to create        : ${BOLD}${TAG}${NC}"
echo ""

# ── Check if tag already exists ─────────────────────────────────────────────
if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo -e "${RED}❌ Tag ${TAG} already exists!${NC}" >&2
  echo -e "   If you want to re-tag, delete it first:" >&2
  echo -e "   git tag -d $TAG && git push origin :refs/tags/$TAG" >&2
  exit 1
fi

# ── Check for uncommitted changes ───────────────────────────────────────────
if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
  echo -e "${YELLOW}⚠️  You have uncommitted changes!${NC}"
  echo -e "   Commit or stash them before tagging a release."
  echo ""
  echo -e "   Continue anyway? (y/N) "
  read -r CONFIRM
  if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "Aborted."
    exit 1
  fi
fi

# ── Create tag ──────────────────────────────────────────────────────────────
if [ "$DRY_RUN" = true ]; then
  echo -e "${YELLOW}[DRY RUN]${NC} Would create tag: ${TAG}"
  echo -e "${YELLOW}[DRY RUN]${NC} Would push tag to origin"
else
  echo -e "  Creating tag ${GREEN}${TAG}${NC}..."
  git tag -a "$TAG" -m "Release $FULL_VERSION"

  echo -e "  Pushing tag to origin..."
  git push origin "$TAG"
fi

echo ""
echo -e "${GREEN}${BOLD}🏷️  Tagged release ${TAG}${NC}"
echo ""
