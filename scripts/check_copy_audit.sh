#!/usr/bin/env bash
# scripts/check_copy_audit.sh
#
# Batch 1 Copy Audit — verifies that forbidden dark-pattern phrases are
# absent from PRODUCTION server source code (excluding test files).
#
# Exit code: 0 = PASS, 1 = FAIL

set -euo pipefail

SERVER_DIR="$(cd "$(dirname "$0")/.." && pwd)/server/src"

if [ ! -d "$SERVER_DIR" ]; then
  echo "ERROR: server/src/ directory not found at $SERVER_DIR"
  exit 1
fi

echo "=== Batch 1 Copy Audit ==="
echo "Searching: $SERVER_DIR (excluding __tests__/)"
echo ""

# Phrases that must NEVER appear in production server code.
# P1.1: "addictively", "emotionally devastating" — manipulation intent
# P1.2: "QUEST_KARMA_BY_TYPE" — variable karma (Skinner box)
# P1.4: "Z_SCORE_THRESHOLD" — only in emotional_attachment/ (silent-alarm was renamed)
#        The trackc/ module has its OWN Z_SCORE_THRESHOLD for analytics anomaly
#        detection, which is OUT OF P1.4 SCOPE (different module, not Silent Alarm).
FORBIDDEN_GLOBAL=(
  "addictively"
  "emotionally devastating"
  "QUEST_KARMA_BY_TYPE"
)

# Guilt/urgency phrases checked only in emotional_attachment/ production code
GUILT_PHRASES=(
  "don't forget"
  "haven't spoken"
  "goes a long way"
  "turn things around"
  "Be the first"
  "last chance"
  "don't miss"
)

FAILURES=0

echo "--- P1.1 + P1.2: Manipulation-intent + variable karma (all server/src/, excluding tests) ---"
for phrase in "${FORBIDDEN_GLOBAL[@]}"; do
  # Search .ts files, exclude __tests__ directories
  matches=$(find "$SERVER_DIR" -name '*.ts' -not -path '*/__tests__/*' -exec grep -lni "$phrase" {} + 2>/dev/null || true)
  if [ -n "$matches" ]; then
    echo "FAIL: Found \"$phrase\" in production code:"
    find "$SERVER_DIR" -name '*.ts' -not -path '*/__tests__/*' -exec grep -ni "$phrase" {} + 2>/dev/null || true
    FAILURES=$((FAILURES + 1))
  else
    echo "PASS: \"$phrase\" not found in production code"
  fi
done

echo ""
echo "--- P1.4: Z_SCORE_THRESHOLD in emotional_attachment/ (was silent-alarm) ---"
EA_DIR="$SERVER_DIR/emotional_attachment"
if [ -d "$EA_DIR" ]; then
  z_matches=$(find "$EA_DIR" -name '*.ts' -not -path '*/__tests__/*' -exec grep -ni "Z_SCORE_THRESHOLD" {} + 2>/dev/null || true)
  if [ -n "$z_matches" ]; then
    echo "FAIL: Z_SCORE_THRESHOLD found in emotional_attachment/:"
    echo "$z_matches"
    FAILURES=$((FAILURES + 1))
  else
    echo "PASS: Z_SCORE_THRESHOLD not found in emotional_attachment/"
  fi
else
  echo "FAIL: emotional_attachment/ directory not found"
  FAILURES=$((FAILURES + 1))
fi

echo ""
echo "--- Guilt/urgency phrases (emotional_attachment/, excluding tests) ---"
if [ -d "$EA_DIR" ]; then
  for phrase in "${GUILT_PHRASES[@]}"; do
    matches=$(find "$EA_DIR" -name '*.ts' -not -path '*/__tests__/*' -exec grep -ni "$phrase" {} + 2>/dev/null || true)
    if [ -n "$matches" ]; then
      echo "FAIL: Found \"$phrase\" in production code:"
      echo "$matches"
      FAILURES=$((FAILURES + 1))
    else
      echo "PASS: \"$phrase\" not found in production code"
    fi
  done
fi

echo ""
echo "=== Copy Audit Result ==="
if [ "$FAILURES" -gt 0 ]; then
  echo "FAIL: $FAILURES forbidden phrase(s) found"
  exit 1
else
  echo "PASS: No forbidden phrases found in production code"
  exit 0
fi
