#!/bin/sh
# =============================================================================
# Daxelo-Kinrel — Docker Entrypoint
# =============================================================================
# Runs Prisma migrations before starting the application.
# This ensures the database schema is up-to-date on every deploy.
#
# Environment variables:
#   RUN_MIGRATIONS — set to "true" to run migrations (default: true in production)
#   SKIP_MIGRATIONS — set to "true" to skip migrations entirely
# =============================================================================

# Note: We intentionally do NOT use `set -e` globally because migration
# failures should not prevent the app from starting. The app handles a
# missing/partial DB gracefully at runtime.

# Determine if migrations should run
RUN_MIGRATIONS="${RUN_MIGRATIONS:-true}"

if [ "$SKIP_MIGRATIONS" = "true" ]; then
  echo "⏭️  Skipping migrations (SKIP_MIGRATIONS=true)"
elif [ "$RUN_MIGRATIONS" = "true" ] && [ -n "$DATABASE_URL" ]; then
  echo "🔄 Running Prisma migrations..."
  if npx prisma migrate deploy; then
    echo "✅ Migrations complete"
  else
    echo "⚠️  prisma migrate deploy failed — attempting prisma db push as fallback..."
    if npx prisma db push --accept-data-loss --skip-generate 2>&1; then
      echo "✅ Database schema synced via db push"
    else
      echo "⚠️  Database schema sync also failed — starting app anyway (DB features may be unavailable)"
    fi
  fi
else
  echo "⏭️  Skipping migrations (RUN_MIGRATIONS=$RUN_MIGRATIONS, DATABASE_URL set: $([ -n "$DATABASE_URL" ] && echo 'yes' || echo 'no'))"
fi

# Start the application
echo "🚀 Starting Daxelo-Kinrel server..."
exec node dist/main
