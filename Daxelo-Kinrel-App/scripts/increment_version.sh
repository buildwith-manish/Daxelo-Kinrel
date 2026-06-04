#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# DAXELO KINREL — Version Increment Script
#
# Reads the current version from pubspec.yaml, increments the build number
# (versionCode) by 1, and optionally bumps the semver component.
#
# Usage:
#   ./scripts/increment_version.sh [patch|minor|major]
#
# Examples:
#   1.0.0+1  →  ./increment_version.sh patch  →  1.0.1+2
#   1.0.0+1  →  ./increment_version.sh minor  →  1.1.0+2
#   1.0.0+1  →  ./increment_version.sh major  →  2.0.0+2
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Locate pubspec.yaml ─────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PUBSPEC="$PROJECT_DIR/pubspec.yaml"

if [ ! -f "$PUBSPEC" ]; then
  echo "❌ pubspec.yaml not found at $PUBSPEC" >&2
  exit 1
fi

# ── Parse bump type ─────────────────────────────────────────────────────────
BUMP="${1:-patch}"

if [[ "$BUMP" != "patch" && "$BUMP" != "minor" && "$BUMP" != "major" ]]; then
  echo "❌ Invalid bump type: $BUMP" >&2
  echo "   Usage: $0 [patch|minor|major]" >&2
  exit 1
fi

# ── Extract current version string ──────────────────────────────────────────
# Format: version: X.Y.Z+B  (may have trailing whitespace or comments)
CURRENT_LINE=$(sed -n 's/^version:[[:space:]]*//p' "$PUBSPEC" | head -1)

if [ -z "$CURRENT_LINE" ]; then
  echo "❌ Could not find 'version:' in pubspec.yaml" >&2
  exit 1
fi

# Strip any inline comments (not standard in YAML but defensive)
VERSION_STRING=$(echo "$CURRENT_LINE" | awk '{print $1}')

# Split into semver and build number
SEMVER="${VERSION_STRING%%+*}"
BUILD="${VERSION_STRING##*+}"

if [ -z "$SEMVER" ] || [ -z "$BUILD" ]; then
  echo "❌ Invalid version format: $VERSION_STRING (expected X.Y.Z+B)" >&2
  exit 1
fi

# Split semver into components
IFS='.' read -r MAJOR MINOR PATCH <<< "$SEMVER"

# Validate components are numeric
if ! [[ "$MAJOR" =~ ^[0-9]+$ && "$MINOR" =~ ^[0-9]+$ && "$PATCH" =~ ^[0-9]+$ && "$BUILD" =~ ^[0-9]+$ ]]; then
  echo "❌ Non-numeric version components: $SEMVER+$BUILD" >&2
  exit 1
fi

# ── Apply bump ──────────────────────────────────────────────────────────────
case "$BUMP" in
  major)
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
    ;;
  minor)
    MINOR=$((MINOR + 1))
    PATCH=0
    ;;
  patch)
    PATCH=$((PATCH + 1))
    ;;
esac

NEW_BUILD=$((BUILD + 1))
NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}+${NEW_BUILD}"

# ── Update pubspec.yaml ────────────────────────────────────────────────────
# Escape regex-special characters in VERSION_STRING for the sed pattern
ESCAPED_VERSION=$(printf '%s\n' "$VERSION_STRING" | sed 's/[.[\*^$()+?{|\\]/\\&/g')

if [[ "$(uname)" == "Darwin" ]]; then
  # macOS sed requires -E for extended regex and '' for in-place
  sed -i '' -E "s|^version:[[:space:]]+${ESCAPED_VERSION}|version: ${NEW_VERSION}|" "$PUBSPEC"
else
  # GNU sed
  sed -i -E "s|^version:[[:space:]]+${ESCAPED_VERSION}|version: ${NEW_VERSION}|" "$PUBSPEC"
fi

# ── Confirm ─────────────────────────────────────────────────────────────────
echo "✅ Version bumped ($BUMP)"
echo "   ${VERSION_STRING}  →  ${NEW_VERSION}"
echo ""
echo "   versionName : ${MAJOR}.${MINOR}.${PATCH}"
echo "   versionCode : ${NEW_BUILD}"
