#!/bin/bash
# ──────────────────────────────────────────────────────────────────────────────
# DAXELO KINREL — Pre-Launch Checklist
#
# Runs ALL checks before submitting to Play Store.
# Exits with code 1 if ANY check fails (warnings do not cause failure).
#
# Usage:
#   ./scripts/pre_launch_check.sh
#   ./scripts/pre_launch_check.sh --skip-build   # Skip the AAB build step
# ──────────────────────────────────────────────────────────────────────────────

set -uo pipefail

# ── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ── Counters ─────────────────────────────────────────────────────────────────
PASSED=0
FAILED=0
WARNINGS=0

# ── Locate project root ─────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKEND_DIR="$(cd "$PROJECT_DIR/../backend" 2>/dev/null && pwd || echo "")"

cd "$PROJECT_DIR"

# ── Parse flags ──────────────────────────────────────────────────────────────
SKIP_BUILD=false
if [[ "${1:-}" == "--skip-build" ]]; then
  SKIP_BUILD=true
fi

# ── Helper functions ─────────────────────────────────────────────────────────
pass() {
  echo -e "  ${GREEN}✅ PASS${NC}  $1"
  ((PASSED++))
}

fail() {
  echo -e "  ${RED}❌ FAIL${NC}  $1"
  ((FAILED++))
}

warn() {
  echo -e "  ${YELLOW}⚠️  WARN${NC}  $1"
  ((WARNINGS++))
}

section() {
  echo ""
  echo -e "${BOLD}${CYAN}━━━ $1 ━━━${NC}"
}

# ══════════════════════════════════════════════════════════════════════════════
echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║        DAXELO KINREL — Pre-Launch Checklist                ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# ══════════════════════════════════════════════════════════════════════════════
# FLUTTER CHECKS
# ══════════════════════════════════════════════════════════════════════════════
section "FLUTTER CHECKS"

# ── 1. flutter analyze — zero errors ────────────────────────────────────────
echo -e "  ${BOLD}Running flutter analyze...${NC}"
ANALYZE_OUTPUT=$(flutter analyze 2>&1) || true
# Check for "error •" pattern in output
if echo "$ANALYZE_OUTPUT" | grep -qE "No issues found"; then
  pass "flutter analyze — no issues found"
elif ! echo "$ANALYZE_OUTPUT" | grep -qE " error •"; then
  pass "flutter analyze — zero errors (warnings/info OK)"
else
  fail "flutter analyze — errors found"
  echo "$ANALYZE_OUTPUT" | grep -E " error •" | head -5 | while read -r line; do
    echo -e "         $line"
  done
fi

# ── 2. flutter test — all unit tests pass ───────────────────────────────────
echo -e "  ${BOLD}Running flutter test...${NC}"
if flutter test 2>&1; then
  pass "flutter test — all unit tests pass"
else
  fail "flutter test — some tests failed"
fi

# ── 3. flutter build appbundle --release ────────────────────────────────────
AAB_BUILT=false
KEY_PROPERTIES="$PROJECT_DIR/android/key.properties"

if [ "$SKIP_BUILD" = true ]; then
  warn "AAB build skipped (--skip-build flag)"
elif [ ! -f "$KEY_PROPERTIES" ]; then
  warn "AAB build skipped — no keystore (key.properties not found)"
else
  echo -e "  ${BOLD}Building release AAB...${NC}"
  if flutter build appbundle --release 2>&1; then
    AAB_BUILT=true
    pass "flutter build appbundle --release — succeeded"
  else
    fail "flutter build appbundle --release — failed"
  fi
fi

# ── 4. AAB file exists at expected path ─────────────────────────────────────
AAB_PATH="$PROJECT_DIR/build/app/outputs/bundle/release/app-release.aab"
if [ "$AAB_BUILT" = true ]; then
  if [ -f "$AAB_PATH" ]; then
    pass "AAB file exists at $AAB_PATH"
  else
    fail "AAB file not found at expected path: $AAB_PATH"
  fi
elif [ -f "$AAB_PATH" ]; then
  pass "AAB file exists (from previous build) at $AAB_PATH"
else
  warn "AAB file not checked (build was skipped)"
fi

# ── 5. AAB size < 150MB ────────────────────────────────────────────────────
if [ -f "$AAB_PATH" ]; then
  AAB_SIZE_BYTES=$(stat -f%z "$AAB_PATH" 2>/dev/null || stat -c%s "$AAB_PATH" 2>/dev/null || echo "0")
  AAB_SIZE_MB=$((AAB_SIZE_BYTES / 1024 / 1024))
  if [ "$AAB_SIZE_BYTES" -lt 157286400 ]; then  # 150 * 1024 * 1024
    pass "AAB size is ${AAB_SIZE_MB}MB (< 150MB Play Store limit)"
  else
    fail "AAB size is ${AAB_SIZE_MB}MB — exceeds 150MB Play Store limit"
  fi
else
  warn "AAB size not checked (no AAB file)"
fi

# ── 6. pubspec.yaml versionCode > 0 ────────────────────────────────────────
VERSION_LINE=$(grep -E "^version:" "$PROJECT_DIR/pubspec.yaml" | head -1)
VERSION_CODE=$(echo "$VERSION_LINE" | sed -E 's/^version:[[:space:]]*[^+]+\+([0-9]+)$/\1/')
if [ -n "$VERSION_CODE" ] && [ "$VERSION_CODE" -gt 0 ] 2>/dev/null; then
  pass "pubspec.yaml versionCode is $VERSION_CODE (> 0)"
else
  fail "pubspec.yaml versionCode is invalid or missing (got: '$VERSION_CODE')"
fi

# ── 7. GoogleFonts.config.allowRuntimeFetching is false ─────────────────────
MAIN_DART="$PROJECT_DIR/lib/main.dart"
if [ -f "$MAIN_DART" ]; then
  if grep -q "GoogleFonts.config.allowRuntimeFetching = false" "$MAIN_DART"; then
    pass "GoogleFonts.config.allowRuntimeFetching = false in main.dart"
  else
    fail "GoogleFonts.config.allowRuntimeFetching is not set to false in main.dart"
  fi
else
  fail "lib/main.dart not found"
fi

# ── 8. No print() calls in lib/ (excluding debugPrint) ──────────────────────
# Search for `print(` but exclude `debugPrint(` and other legitimate uses
PRINT_VIOLATIONS=$(grep -rn "print(" "$PROJECT_DIR/lib/" \
  --include="*.dart" \
  | grep -v "debugPrint(" \
  | grep -v "blueprint" \
  | grep -v "sprint" \
  | grep -v "fingerprint" \
  | grep -v "printError" \
  | grep -v "footprint" \
  || true)
# Further filter: only lines where print( is a standalone call, not part of another word
FILTERED_VIOLATIONS=""
while IFS= read -r line; do
  [ -z "$line" ] && continue
  # Check if the line contains a raw print( call (preceded by whitespace or start)
  if echo "$line" | grep -qE "(^|[^a-zA-Z])print\("; then
    # But exclude debugPrint
    if ! echo "$line" | grep -q "debugPrint"; then
      FILTERED_VIOLATIONS="${FILTERED_VIOLATIONS}${line}"$'\n'
    fi
  fi
done <<< "$PRINT_VIOLATIONS"

if [ -z "$FILTERED_VIOLATIONS" ]; then
  pass "No raw print() calls in lib/ (debugPrint OK)"
else
  VIOLATION_COUNT=$(echo "$FILTERED_VIOLATIONS" | grep -c "print(" || true)
  fail "Found $VIOLATION_COUNT raw print() call(s) in lib/ — use logging package instead"
  echo "$FILTERED_VIOLATIONS" | head -5 | while read -r line; do
    [ -n "$line" ] && echo -e "         $line"
  done
fi

# ── 9. No hardcoded API URLs in lib/ (outside config files) ─────────────────
# Search for http:// or https:// URLs in lib/ excluding config files
HARDCODED_URLS=$(grep -rn "https\?://" "$PROJECT_DIR/lib/" \
  --include="*.dart" \
  | grep -v "lib/core/config/" \
  | grep -v "url_launcher" \
  | grep -v "launchUrl" \
  | grep -v "Uri.parse" \
  | grep -v "//.*https\?://" \
  || true)
if [ -z "$HARDCODED_URLS" ]; then
  pass "No hardcoded API URLs in lib/ outside config files"
else
  URL_COUNT=$(echo "$HARDCODED_URLS" | wc -l | tr -d ' ')
  fail "Found $URL_COUNT hardcoded URL(s) in lib/ — use FlavorConfig/EnvConfig instead"
  echo "$HARDCODED_URLS" | head -5 | while read -r line; do
    echo -e "         $line"
  done
fi

# ── 10. No TODO comments in lib/core/ or lib/data/ ──────────────────────────
TODO_VIOLATIONS=""
if [ -d "$PROJECT_DIR/lib/core" ]; then
  CORE_TODOS=$(grep -rn "TODO" "$PROJECT_DIR/lib/core/" --include="*.dart" || true)
  TODO_VIOLATIONS="${TODO_VIOLATIONS}${CORE_TODOS}"
fi
if [ -d "$PROJECT_DIR/lib/data" ]; then
  DATA_TODOS=$(grep -rn "TODO" "$PROJECT_DIR/lib/data/" --include="*.dart" || true)
  TODO_VIOLATIONS="${TODO_VIOLATIONS}${DATA_TODOS}"
fi
if [ -z "$TODO_VIOLATIONS" ]; then
  pass "No TODO comments in lib/core/ or lib/data/"
else
  TODO_COUNT=$(echo "$TODO_VIOLATIONS" | grep -c "TODO" || true)
  fail "Found $TODO_COUNT TODO comment(s) in lib/core/ or lib/data/"
  echo "$TODO_VIOLATIONS" | head -5 | while read -r line; do
    echo -e "         $line"
  done
fi

# ══════════════════════════════════════════════════════════════════════════════
# ANDROID CHECKS
# ══════════════════════════════════════════════════════════════════════════════
section "ANDROID CHECKS"

# ── 1. key.properties exists (signing configured) — warn only ───────────────
if [ -f "$KEY_PROPERTIES" ]; then
  pass "key.properties exists — signing configured"
else
  warn "key.properties not found — release signing not configured (copy from key.properties.example)"
fi

# ── 2. applicationId is com.daxelo.kinrel ───────────────────────────────────
APP_BUILD_GRADLE="$PROJECT_DIR/android/app/build.gradle.kts"
if [ -f "$APP_BUILD_GRADLE" ]; then
  if grep -q 'applicationId = "com.daxelo.kinrel"' "$APP_BUILD_GRADLE"; then
    pass "applicationId is com.daxelo.kinrel"
  else
    fail "applicationId is not com.daxelo.kinrel (check build.gradle.kts)"
  fi
else
  fail "android/app/build.gradle.kts not found"
fi

# ── 3. minSdkVersion >= 21 ─────────────────────────────────────────────────
if [ -f "$APP_BUILD_GRADLE" ]; then
  MIN_SDK_LINE=$(grep -E "minSdk\s*=" "$APP_BUILD_GRADLE" | head -1 || true)
  if echo "$MIN_SDK_LINE" | grep -qE "minSdk\s*=\s*[0-9]+"; then
    MIN_SDK=$(echo "$MIN_SDK_LINE" | sed -E 's/.*minSdk\s*=\s*([0-9]+).*/\1/')
    if [ "$MIN_SDK" -ge 21 ] 2>/dev/null; then
      pass "minSdkVersion is $MIN_SDK (>= 21)"
    else
      fail "minSdkVersion is $MIN_SDK — must be >= 21"
    fi
  elif echo "$MIN_SDK_LINE" | grep -q "flutter.minSdkVersion"; then
    pass "minSdkVersion uses flutter.minSdkVersion (default >= 21)"
  else
    warn "Could not determine minSdkVersion from build.gradle.kts"
  fi
else
  fail "Cannot check minSdkVersion — build.gradle.kts not found"
fi

# ── 4. targetSdkVersion is set ──────────────────────────────────────────────
if [ -f "$APP_BUILD_GRADLE" ]; then
  TARGET_SDK_LINE=$(grep -E "targetSdk\s*=" "$APP_BUILD_GRADLE" | head -1 || true)
  if [ -n "$TARGET_SDK_LINE" ]; then
    if echo "$TARGET_SDK_LINE" | grep -qE "targetSdk\s*=\s*[0-9]+"; then
      TARGET_SDK=$(echo "$TARGET_SDK_LINE" | sed -E 's/.*targetSdk\s*=\s*([0-9]+).*/\1/')
      pass "targetSdkVersion is set to $TARGET_SDK"
    elif echo "$TARGET_SDK_LINE" | grep -q "flutter.targetSdkVersion"; then
      pass "targetSdkVersion uses flutter.targetSdkVersion (set)"
    else
      warn "targetSdkVersion reference found but value unclear"
    fi
  else
    fail "targetSdkVersion not set in build.gradle.kts"
  fi
else
  fail "Cannot check targetSdkVersion — build.gradle.kts not found"
fi

# ── 5. No cleartext traffic in release manifest ─────────────────────────────
NET_SEC_CONFIG="$PROJECT_DIR/android/app/src/main/res/xml/network_security_config.xml"
if [ -f "$NET_SEC_CONFIG" ]; then
  BASE_CONFIG=$(grep -A2 "<base-config" "$NET_SEC_CONFIG" | head -3 || true)
  if echo "$BASE_CONFIG" | grep -q 'cleartextTrafficPermitted="false"'; then
    pass "Network security config blocks cleartext traffic in base-config"
  else
    fail "base-config does not block cleartext traffic — set cleartextTrafficPermitted=\"false\""
  fi
else
  fail "network_security_config.xml not found"
fi

# ── 6. Proguard rules file exists ───────────────────────────────────────────
PROGUARD_FILE="$PROJECT_DIR/android/app/proguard-rules.pro"
if [ -f "$PROGUARD_FILE" ]; then
  pass "Proguard rules file exists (proguard-rules.pro)"
else
  fail "Proguard rules file not found (android/app/proguard-rules.pro)"
fi

# ══════════════════════════════════════════════════════════════════════════════
# BACKEND CHECKS
# ══════════════════════════════════════════════════════════════════════════════
section "BACKEND CHECKS"

if [ -n "$BACKEND_DIR" ] && [ -d "$BACKEND_DIR" ]; then
  # ── 1. npm run build — succeeds ───────────────────────────────────────────
  echo -e "  ${BOLD}Running backend build...${NC}"
  if [ -f "$BACKEND_DIR/package.json" ]; then
    if (cd "$BACKEND_DIR" && npm run build 2>&1); then
      pass "Backend npm run build — succeeded"
    else
      fail "Backend npm run build — failed"
    fi
  else
    warn "Backend package.json not found at $BACKEND_DIR"
  fi

  # ── 2. Prisma schema is valid ─────────────────────────────────────────────
  if [ -f "$BACKEND_DIR/prisma/schema.prisma" ]; then
    echo -e "  ${BOLD}Validating Prisma schema...${NC}"
    if (cd "$BACKEND_DIR" && npx prisma validate 2>&1); then
      pass "Prisma schema is valid"
    else
      fail "Prisma schema validation failed"
    fi
  else
    warn "Prisma schema not found at $BACKEND_DIR/prisma/schema.prisma"
  fi
else
  warn "Backend directory not found — skipping backend checks"
  ((WARNINGS++))  # Extra warning for missing backend dir
fi

# ══════════════════════════════════════════════════════════════════════════════
# STORE ASSET CHECKS (warnings only)
# ══════════════════════════════════════════════════════════════════════════════
section "STORE ASSET CHECKS"

STORE_DIR="$PROJECT_DIR/store"

# ── 1. store/feature.png exists (1024×500) ─────────────────────────────────
if [ -f "$STORE_DIR/feature.png" ]; then
  if command -v identify &>/dev/null; then
    DIMS=$(identify -format "%wx%h" "$STORE_DIR/feature.png" 2>/dev/null || echo "unknown")
    pass "store/feature.png exists (${DIMS})"
  else
    pass "store/feature.png exists"
  fi
else
  warn "store/feature.png not found (should be 1024x500)"
fi

# ── 2. store/short_desc.txt <= 80 chars ────────────────────────────────────
if [ -f "$STORE_DIR/short_desc.txt" ]; then
  SHORT_DESC_LEN=$(tr -d '\n' < "$STORE_DIR/short_desc.txt" | wc -m | tr -d ' ')
  if [ "$SHORT_DESC_LEN" -le 80 ]; then
    pass "store/short_desc.txt is ${SHORT_DESC_LEN} chars (<= 80)"
  else
    warn "store/short_desc.txt is ${SHORT_DESC_LEN} chars — exceeds 80 char limit"
  fi
else
  warn "store/short_desc.txt not found (max 80 chars)"
fi

# ── 3. store/full_desc.txt <= 4000 chars ───────────────────────────────────
if [ -f "$STORE_DIR/full_desc.txt" ]; then
  FULL_DESC_LEN=$(tr -d '\n' < "$STORE_DIR/full_desc.txt" | wc -m | tr -d ' ')
  if [ "$FULL_DESC_LEN" -le 4000 ]; then
    pass "store/full_desc.txt is ${FULL_DESC_LEN} chars (<= 4000)"
  else
    warn "store/full_desc.txt is ${FULL_DESC_LEN} chars — exceeds 4000 char limit"
  fi
else
  warn "store/full_desc.txt not found (max 4000 chars)"
fi

# ── 4. store/privacy_url.txt exists ────────────────────────────────────────
if [ -f "$STORE_DIR/privacy_url.txt" ]; then
  pass "store/privacy_url.txt exists"
else
  warn "store/privacy_url.txt not found"
fi

# ── 5. At least 2 phone screenshots ────────────────────────────────────────
SCREENSHOT_DIR="$STORE_DIR/screenshots"
if [ -d "$SCREENSHOT_DIR" ]; then
  PHONE_SCREENSHOTS=$(find "$SCREENSHOT_DIR" -maxdepth 1 -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" \) 2>/dev/null | wc -l | tr -d ' ')
  if [ "$PHONE_SCREENSHOTS" -ge 2 ]; then
    pass "Found $PHONE_SCREENSHOTS phone screenshot(s) in store/screenshots/"
  else
    warn "Only $PHONE_SCREENSHOTS phone screenshot(s) found — need at least 2"
  fi
else
  warn "store/screenshots/ directory not found — need at least 2 phone screenshots"
fi

# ══════════════════════════════════════════════════════════════════════════════
# SUMMARY
# ══════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  PRE-LAUNCH CHECKLIST SUMMARY${NC}"
echo -e "${BOLD}═══════════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${GREEN}✅ PASSED:${NC}   $PASSED checks"
echo -e "  ${RED}❌ FAILED:${NC}   $FAILED checks"
echo -e "  ${YELLOW}⚠️  WARNINGS:${NC} $WARNINGS checks"
echo ""

if [ "$FAILED" -eq 0 ]; then
  echo -e "  ${GREEN}${BOLD}🎉 Ready to submit! All critical checks passed.${NC}"
  echo ""
  exit 0
else
  echo -e "  ${RED}${BOLD}🚫 NOT ready to submit. Fix the $FAILED failing check(s) above.${NC}"
  echo ""
  exit 1
fi
