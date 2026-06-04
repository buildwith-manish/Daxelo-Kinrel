#!/usr/bin/env bash
#
# Store Assets Checklist — Play Store Listing
# Verifies all required assets exist and meet size/content constraints.
#
set -uo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() { echo -e "  ${GREEN}✅${NC} $1"; }
fail() { echo -e "  ${RED}❌${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠️${NC}  $1"; }

errors=0

echo ""
echo "========================================"
echo "  Play Store Listing — Asset Checklist"
echo "========================================"
echo ""

# ── 1. App Icon 512×512 PNG ──────────────────────────────────────────
ICON_PATH="$PROJECT_ROOT/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"
echo "1. App Icon 512×512 PNG (mipmap-xxxhdpi/ic_launcher.png)"
if [[ -f "$ICON_PATH" ]]; then
  pass "File exists: $ICON_PATH"
  # Check dimensions if ImageMagick identify is available
  if command -v identify &>/dev/null; then
    dims=$(identify -format "%wx%h" "$ICON_PATH" 2>/dev/null || echo "unknown")
    if [[ "$dims" == "512x512" ]]; then
      pass "Dimensions: 512×512 ✓"
    else
      warn "Dimensions: $dims (expected 512×512)"
    fi
  else
    warn "ImageMagick 'identify' not available — skipping dimension check"
  fi
else
  fail "Missing: $ICON_PATH"
  ((errors++))
fi
echo ""

# ── 2. Feature Graphic 1024×500 PNG ──────────────────────────────────
FEATURE_PATH="$PROJECT_ROOT/store/feature.png"
echo "2. Feature Graphic 1024×500 PNG (store/feature.png)"
if [[ -f "$FEATURE_PATH" ]]; then
  pass "File exists: $FEATURE_PATH"
  if command -v identify &>/dev/null; then
    dims=$(identify -format "%wx%h" "$FEATURE_PATH" 2>/dev/null || echo "unknown")
    if [[ "$dims" == "1024x500" ]]; then
      pass "Dimensions: 1024×500 ✓"
    else
      warn "Dimensions: $dims (expected 1024×500)"
    fi
  else
    warn "ImageMagick 'identify' not available — skipping dimension check"
  fi
else
  fail "Missing: $FEATURE_PATH"
  ((errors++))
fi
echo ""

# ── 3. Phone Screenshots (min 2, max 8) ──────────────────────────────
SCREENSHOT_DIR="$PROJECT_ROOT/store/screenshots"
echo "3. Phone Screenshots (store/screenshots/phone_*.png) — min 2, max 8"
phone_count=0
if [[ -d "$SCREENSHOT_DIR" ]]; then
  phone_count=$(find "$SCREENSHOT_DIR" -maxdepth 1 -name 'phone_*.png' 2>/dev/null | wc -l | tr -d ' ')
fi
if [[ "$phone_count" -ge 2 && "$phone_count" -le 8 ]]; then
  pass "Phone screenshots: $phone_count (within 2–8 range)"
elif [[ "$phone_count" -lt 2 ]]; then
  fail "Phone screenshots: $phone_count (need at least 2)"
  ((errors++))
else
  warn "Phone screenshots: $phone_count (exceeds max of 8)"
fi
echo ""

# ── 4. Tablet 7" Screenshots ─────────────────────────────────────────
echo "4. Tablet 7\" Screenshots (store/screenshots/tablet7_*.png)"
tablet7_count=0
if [[ -d "$SCREENSHOT_DIR" ]]; then
  tablet7_count=$(find "$SCREENSHOT_DIR" -maxdepth 1 -name 'tablet7_*.png' 2>/dev/null | wc -l | tr -d ' ')
fi
if [[ "$tablet7_count" -gt 0 ]]; then
  pass "Tablet 7\" screenshots: $tablet7_count"
else
  fail "No tablet 7\" screenshots found"
  ((errors++))
fi
echo ""

# ── 5. Short Description (≤ 80 chars) ────────────────────────────────
SHORT_DESC_PATH="$PROJECT_ROOT/store/short_desc.txt"
echo "5. Short Description (store/short_desc.txt) — max 80 chars"
if [[ -f "$SHORT_DESC_PATH" ]]; then
  pass "File exists: $SHORT_DESC_PATH"
  char_count_no_nl=$(tr -d '\n' < "$SHORT_DESC_PATH" | wc -c | tr -d ' ')
  if [[ "$char_count_no_nl" -le 80 ]]; then
    pass "Character count: $char_count_no_nl (≤ 80) ✓"
  else
    fail "Character count: $char_count_no_nl (exceeds 80)"
    ((errors++))
  fi
else
  fail "Missing: $SHORT_DESC_PATH"
  ((errors++))
fi
echo ""

# ── 6. Full Description (≤ 4000 chars) ───────────────────────────────
FULL_DESC_PATH="$PROJECT_ROOT/store/full_desc.txt"
echo "6. Full Description (store/full_desc.txt) — max 4000 chars"
if [[ -f "$FULL_DESC_PATH" ]]; then
  pass "File exists: $FULL_DESC_PATH"
  char_count_no_nl=$(tr -d '\n' < "$FULL_DESC_PATH" | wc -c | tr -d ' ')
  if [[ "$char_count_no_nl" -le 4000 ]]; then
    pass "Character count: $char_count_no_nl (≤ 4000) ✓"
  else
    fail "Character count: $char_count_no_nl (exceeds 4000)"
    ((errors++))
  fi
else
  fail "Missing: $FULL_DESC_PATH"
  ((errors++))
fi
echo ""

# ── 7. Content Rating ────────────────────────────────────────────────
CONTENT_RATING_PATH="$PROJECT_ROOT/store/content_rating.txt"
echo "7. Content Rating (store/content_rating.txt)"
if [[ -f "$CONTENT_RATING_PATH" ]]; then
  pass "File exists: $CONTENT_RATING_PATH"
else
  fail "Missing: $CONTENT_RATING_PATH"
  ((errors++))
fi
echo ""

# ── 8. Privacy Policy URL ────────────────────────────────────────────
PRIVACY_URL_PATH="$PROJECT_ROOT/store/privacy_url.txt"
echo "8. Privacy Policy URL (store/privacy_url.txt)"
if [[ -f "$PRIVACY_URL_PATH" ]]; then
  pass "File exists: $PRIVACY_URL_PATH"
  url=$(tr -d '\n' < "$PRIVACY_URL_PATH")
  if [[ "$url" =~ ^https?:// ]]; then
    pass "Valid URL: $url"
  else
    fail "Invalid URL: $url (must start with http:// or https://)"
    ((errors++))
  fi
else
  fail "Missing: $PRIVACY_URL_PATH"
  ((errors++))
fi
echo ""

# ── Summary ───────────────────────────────────────────────────────────
echo "========================================"
if [[ "$errors" -eq 0 ]]; then
  echo -e "  ${GREEN}All checks passed! Store listing is ready.${NC}"
else
  echo -e "  ${RED}$errors issue(s) found. Fix before uploading.${NC}"
fi
echo "========================================"
echo ""

exit "$errors"
