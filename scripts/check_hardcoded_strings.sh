#!/usr/bin/env bash
# scripts/check_hardcoded_strings.sh
#
# P6.4 — Localize all UI chrome (CI-enforced).
#
# Scans Flutter Dart files for hardcoded English UI strings (Text widgets
# with string literals) that should use AppLocalizations.of(context).
# Fails if unallowed hardcoded strings are found.
#
# Exit code: 0 = PASS, 1 = FAIL

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$REPO_ROOT/Daxelo-Kinrel-App"
ALLOWLIST="$SCRIPT_DIR/hardcoded_strings_allowlist.txt"

if [ ! -f "$ALLOWLIST" ]; then
  echo "ERROR: Allowlist not found at $ALLOWLIST"
  exit 1
fi

echo "=== P6.4: Hardcoded Strings Check ==="
echo "Scanning: $APP_DIR/lib/ (excluding generated, l10n, test)"
echo ""

# Read allowlist entries (strip comments and empty lines)
ALLOWLIST_ENTRIES=$(grep -v '^#' "$ALLOWLIST" | grep -v '^$' | sed 's/[[:space:]]*$//' || true)

# Function: check if a file path is allowlisted (supports directory prefixes)
is_allowlisted() {
  local rel_path="$1"
  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    # Directory entry (ends with /) or file path
    if [[ "$rel_path" == "$entry"* ]]; then
      return 0
    fi
  done <<< "$ALLOWLIST_ENTRIES"
  return 1
}

# Single grep -rn pass to find all Text('...') or Text("...") matches
# Exclude generated files, l10n, and app_localizations
VIOLATIONS=0
VIOLATION_LIST=""

while IFS=: read -r filepath line_num content; do
  # Skip if not a .dart file (grep might match binary)
  [[ "$filepath" != *.dart ]] && continue

  # Get relative path
  rel_path="${filepath#$APP_DIR/}"

  # Check if file is allowlisted
  if is_allowlisted "$rel_path"; then
    continue
  fi

  # Skip comment lines
  trimmed=$(echo "$content" | sed 's/^[[:space:]]*//')
  case "$trimmed" in
    //*) continue ;;
    \**) continue ;;
  esac

  # Skip if the line contains AppLocalizations or .tr( or S.of
  if echo "$content" | grep -qE "AppLocalizations|S\.of|\.tr\("; then
    continue
  fi

  VIOLATIONS=$((VIOLATIONS + 1))
  VIOLATION_LIST="$VIOLATION_LIST\n  $rel_path:$line_num: $trimmed"
done < <(grep -rn --include="*.dart" -E "Text\('[^']+'\)|Text\(\"[^\"]+\"\)" \
  --exclude="*.g.dart" --exclude="*.freezed.dart" --exclude="app_localizations*" \
  "$APP_DIR/lib" 2>/dev/null | grep -v '/l10n/' || true)

if [ "$VIOLATIONS" -gt 0 ]; then
  echo "FAIL: Found $VIOLATIONS hardcoded English UI strings."
  echo ""
  echo "Violations:"
  echo -e "$VIOLATION_LIST"
  echo ""
  echo "To fix: move strings to .arb files and use AppLocalizations.of(context)."
  echo "To allowlist: add file path to scripts/hardcoded_strings_allowlist.txt"
  exit 1
fi

echo "PASS: No hardcoded English UI strings found."
exit 0
