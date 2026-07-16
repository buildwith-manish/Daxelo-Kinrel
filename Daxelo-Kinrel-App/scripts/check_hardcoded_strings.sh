#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────
# check_hardcoded_strings.sh — P6.4 CI gate
# Scans lib/ for user-visible strings that are NOT localized via
# the l10n .arb system.  Returns 0 if clean, 1 if violations found.
# ─────────────────────────────────────────────────────────────────
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALLOWLIST="${SCRIPT_DIR}/hardcoded_strings_allowlist.txt"

# Directories to scan
SCAN_DIRS=(
  "lib/features"
  "lib/core"
  "lib/shared"
  "lib/graph"
)

# Patterns that indicate a hardcoded user-visible string
# (quoted strings in widget constructors like Text('...'), label: '...', etc.)
# We skip obvious non-user strings: debug prints, asset paths, URLs, keys.
PATTERNS=(
  # Text widgets with string literals
  "Text\(r?['\"]"
  # title/label/subtitle with string literals
  "(title|label|subtitle|hint|helperText|errorText)\s*:\s*r?['\"]"
  # SnackBar / Dialog content
  "content:\s*r?['\"]"
)

VIOLATIONS=0

# Build allowlist lookup
declare -A ALLOWED
if [ -f "$ALLOWLIST" ]; then
  while IFS= read -r line; do
    # Skip comments and empty lines
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ -z "${line// /}" ]] && continue
    ALLOWED["$line"]=1
  done < "$ALLOWLIST"
fi

for dir in "${SCAN_DIRS[@]}"; do
  if [ ! -d "$dir" ]; then
    continue
  fi

  while IFS= read -r file; do
    # Skip generated files
    [[ "$file" == *.g.dart ]] && continue
    [[ "$file" == *.freezed.dart ]] && continue
    [[ "$file" == *.config.dart ]] && continue

    # Check for hardcoded string patterns
    # Look for Text('...') and similar widget patterns with literal strings
    while IFS=: read -r lineno line; do
      # Skip import statements
      [[ "$line" =~ ^[[:space:]]*import ]] && continue
      # Skip comments
      [[ "$line" =~ ^[[:space:]]*// ]] && continue
      [[ "$line" =~ ^[[:space:]]*\* ]] && continue
      # Skip debug/log statements
      [[ "$line" =~ debugPrint|print\(|log\( ]] && continue
      # Skip asset paths and URLs
      [[ "$line" =~ (assets/|http://|https://|\.png|\.svg|\.json|\.glb) ]] && continue
      # Skip enum/const values
      [[ "$line" =~ enum |const  ]] && continue

      # Check for un-localized user-visible strings
      if echo "$line" | grep -qP "Text\(r?['\"]([A-Z][a-zA-Z ]{2,})"; then
        # Extract the string
        matched=$(echo "$line" | grep -oP "Text\(r?['\"]([A-Z][a-zA-Z ]{2,})" | head -1)
        # Check allowlist
        if [ -z "${ALLOWED[$matched]+x}" ]; then
          echo "VIOLATION: $file:$lineno — $matched"
          VIOLATIONS=$((VIOLATIONS + 1))
        fi
      fi
    done < <(grep -n "Text(" "$file" 2>/dev/null || true)
  done < <(find "$dir" -name "*.dart" -type f 2>/dev/null)
done

if [ "$VIOLATIONS" -gt 0 ]; then
  echo ""
  echo "FOUND $VIOLATIONS hardcoded string violation(s)."
  echo "Add entries to $ALLOWLIST or replace with l10n keys."
  exit 1
fi

echo "P6.4 PASS — No un-localized user-visible strings found."
exit 0
