#!/bin/bash
# =============================================================================
# Daxelo-Kinrel — Pre-Start Environment Validation
# =============================================================================
# Validates that all required environment variables are set before starting
# the server. Run this as part of the container startup or CI/CD pipeline.
#
# Usage:
#   chmod +x scripts/pre-start.sh
#   ./scripts/pre-start.sh
#   # Or in Dockerfile:
#   CMD ["sh", "-c", "./scripts/pre-start.sh && node dist/main.js"]
# =============================================================================

set -euo pipefail

# ── Required Variables (server will NOT start without these) ───────────────
REQUIRED_VARS=(
  "DATABASE_URL"
  "JWT_ACCESS_SECRET"
  "SUPABASE_JWT_SECRET"
  "SUPABASE_ANON_KEY"
  "SUPABASE_URL"
)

# ── Optional but Recommended (warnings if missing) ────────────────────────
RECOMMENDED_VARS=(
  "GEMINI_API_KEY"
  "CORS_ORIGINS"
)

MISSING=()
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var:-}" ]; then
    MISSING+=("$var")
  fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "ERROR: Missing required environment variables:"
  printf '  - %s\n' "${MISSING[@]}"
  exit 1
fi

echo "✅ All required environment variables are set"

# ── Check recommended variables ───────────────────────────────────────────
WARNINGS=()
for var in "${RECOMMENDED_VARS[@]}"; do
  if [ -z "${!var:-}" ]; then
    WARNINGS+=("$var")
  fi
done

if [ ${#WARNINGS[@]} -gt 0 ]; then
  echo "⚠️  Warning: Recommended environment variables not set:"
  printf '  - %s\n' "${WARNINGS[@]}"
  echo "Some features may not work correctly without these."
fi
