#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────
# env_check.sh – Validate required environment variables
# Run in CI before deploy. Exit 1 if any required var is missing.
# Usage: bash scripts/env_check.sh
# ──────────────────────────────────────────────────────────

set -euo pipefail

IS_PROD=false
if [[ "${NODE_ENV:-}" == "production" ]]; then
  IS_PROD=true
fi

ERRORS=0

check_var() {
  local name="$1"
  local required="${2:-true}"  # true = always required, prod = only in production
  local min_len="${3:-0}"

  local value="${!name:-}"

  if [[ -z "$value" ]]; then
    if [[ "$required" == "true" ]]; then
      echo "❌  $name — not set"
      ERRORS=$((ERRORS + 1))
    elif [[ "$required" == "prod" && "$IS_PROD" == "true" ]]; then
      echo "❌  $name — not set (required in production)"
      ERRORS=$((ERRORS + 1))
    else
      echo "✅  $name — (optional, not set)"
    fi
    return
  fi

  # Check minimum length
  if [[ "$min_len" -gt 0 && ${#value} -lt "$min_len" ]]; then
    echo "❌  $name — set but too short (${#value} chars, minimum $min_len)"
    ((ERRORS++))
    return
  fi

  echo "✅  $name — set (${#value} chars)"
}

echo ""
echo "══════════════════════════════════════════════════"
echo "  Production Environment Check"
echo "  NODE_ENV=${NODE_ENV:-<not set>}"
echo "══════════════════════════════════════════════════"
echo ""

# ── Always required ────────────────────────────────────────
check_var "NODE_ENV"          "true"
check_var "PORT"              "true"
check_var "DATABASE_URL"      "true"
check_var "JWT_SECRET"        "true"  "$($IS_PROD && echo 64 || echo 32)"
check_var "JWT_REFRESH_SECRET" "true" "$($IS_PROD && echo 64 || echo 32)"
check_var "LOG_LEVEL"         "true"

# ── Production-only required ───────────────────────────────
check_var "APP_URL"                    "prod"
check_var "CLOUDINARY_CLOUD_NAME"      "prod"
check_var "CLOUDINARY_API_KEY"         "prod"
check_var "CLOUDINARY_API_SECRET"      "prod"
check_var "FIREBASE_SERVICE_ACCOUNT_JSON" "prod"

# ── Optional (never fails) ─────────────────────────────────
check_var "RAZORPAY_KEY_ID"   "false"
check_var "RAZORPAY_KEY_SECRET" "false"
check_var "LOGTAIL_TOKEN"     "false"
check_var "THROTTLE_TTL"      "false"
check_var "THROTTLE_LIMIT"    "false"

echo ""
echo "══════════════════════════════════════════════════"

if [[ "$ERRORS" -gt 0 ]]; then
  echo "  ❌  $ERRORS error(s) found — deploy blocked"
  echo "══════════════════════════════════════════════════"
  exit 1
else
  echo "  ✅  All required variables are set"
  echo "══════════════════════════════════════════════════"
  exit 0
fi
