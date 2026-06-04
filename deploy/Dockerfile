# =============================================================================
# Daxelo-Kinrel — Dockerfile for Render Deployment
# =============================================================================
# Multi-stage build that:
#   - Uses Node 20 (NestJS 11 requires >= 20) — bypasses Render NODE_VERSION
#   - Runs npm ci WITHOUT NODE_ENV=production — installs ALL deps including dev
#   - Builds the NestJS app inside Docker
#   - Produces a minimal production image with only runtime artefacts
# =============================================================================

# ── Stage 1: Build ──────────────────────────────────────────────────
FROM node:20-alpine AS builder
WORKDIR /app

# Install dependencies first (leverage Docker layer caching)
# NOTE: NODE_ENV is NOT set here — this ensures npm ci installs
# devDependencies (prisma, @nestjs/cli, typescript) which are needed for build
COPY package*.json ./
COPY .npmrc ./
RUN npm ci

# Copy source and build
COPY . .
RUN npx prisma generate
RUN npm run build

# Prune devDependencies after build — keeps only production deps for runner
RUN npm prune --omit=dev

# ── Stage 2: Production ────────────────────────────────────────────
FROM node:20-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production

# Create non-root user for security
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Copy only production artefacts
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/package*.json ./

# Create writable directories for the non-root user
RUN mkdir -p logs && chown -R appuser:appgroup /app

# Use non-root user
USER appuser

# Render provides PORT env var (default 10000).
# The app reads process.env.PORT at runtime (main.ts).
EXPOSE 10000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:${PORT:-10000}/api/health || exit 1

CMD ["node", "dist/main"]
