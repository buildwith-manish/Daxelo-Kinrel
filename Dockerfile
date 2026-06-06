# =============================================================================
# Daxelo-Kinrel — Unified Dockerfile
# =============================================================================
# Consolidates Dockerfile, deploy/Dockerfile, deploy/Dockerfile.koyeb, and
# deploy/Dockerfile.production into a single file with build-arg targets.
#
# Usage:
#   Render (default):   docker build .
#   Koyeb:              docker build --build-arg APP_PORT=3000 .
#   Custom port:        docker build --build-arg APP_PORT=8080 .
#   Slim image:         docker build --build-arg SLIM=true .
#
# Build context MUST be the repo root (not server/).
# =============================================================================

# ── Build Args ────────────────────────────────────────────────────────────────
ARG NODE_VERSION=20
ARG APP_PORT=10000
ARG SLIM=false

# ── Stage 1: Build ───────────────────────────────────────────────────────────
FROM node:${NODE_VERSION}-alpine AS builder
WORKDIR /app

# Install dependencies first (leverage Docker layer caching)
# NOTE: NODE_ENV is NOT set here — ensures devDependencies are installed
COPY server/package*.json server/.npmrc* ./
RUN if [ -f .npmrc ]; then npm ci; else npm install --legacy-peer-deps; fi

# Copy source, generate Prisma, build
COPY server/ .
RUN npx prisma generate
RUN npm run build

# Prune devDependencies after build — keeps only production deps for runner
RUN npm prune --omit=dev

# ── Stage 2: Production ─────────────────────────────────────────────────────
FROM node:${NODE_VERSION}-alpine AS runner

# Re-declare build args for this stage
ARG APP_PORT=10000
ARG SLIM=false

WORKDIR /app

ENV NODE_ENV=production

# Create non-root user for security
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Copy production artefacts from builder
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/package*.json ./

# Copy the entrypoint script from repo root
COPY docker-entrypoint.sh ./
RUN chmod +x docker-entrypoint.sh

# Create writable directories and set ownership
RUN mkdir -p logs && chown -R appuser:appgroup /app

# Switch to non-root user
USER appuser

# Expose port (default 10000 for Render, override with --build-arg APP_PORT=3000 for Koyeb)
EXPOSE ${APP_PORT}

# Health check — configurable start-period for constrained environments
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:${PORT:-${APP_PORT}}/api/health || exit 1

# Start the application via entrypoint (runs Prisma migrations first)
CMD ["./docker-entrypoint.sh"]
