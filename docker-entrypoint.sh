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

set -e

# Determine if migrations should run
RUN_MIGRATIONS="${RUN_MIGRATIONS:-true}"

if [ "$SKIP_MIGRATIONS" = "true" ]; then
  echo "⏭️  Skipping migrations (SKIP_MIGRATIONS=true)"
elif [ "$RUN_MIGRATIONS" = "true" ] && [ -n "$DATABASE_URL" ]; then
  echo "🔄 Running Prisma migrations..."
  npx prisma migrate deploy
  echo "✅ Migrations complete"
else
  echo "⏭️  Skipping migrations (RUN_MIGRATIONS=$RUN_MIGRATIONS, DATABASE_URL set: $([ -n "$DATABASE_URL" ] && echo 'yes' || echo 'no'))"
fi

# Start the application
echo "🚀 Starting Daxelo-Kinrel server..."
exec node dist/main
