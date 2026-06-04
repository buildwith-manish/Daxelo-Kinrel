# =============================================================================
# Daxelo-Kinrel — Dockerfile for Render (at repo root)
# =============================================================================
# Simple multi-stage build that works reliably on Render free tier.
# Copies server/ contents, installs deps, generates Prisma, builds, runs.
# =============================================================================

FROM node:20-alpine AS builder
WORKDIR /app

# Copy server package files and install ALL deps (including dev for build)
COPY server/package*.json server/.npmrc ./
RUN npm install --legacy-peer-deps

# Copy server source and build
COPY server/ .
RUN npx prisma generate
RUN npm run build

# Prune devDependencies after build
RUN npm prune --omit=dev

# ── Stage 2: Production ────────────────────────────────────────────
FROM node:20-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production

# Create non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

# Copy production artefacts
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/package*.json ./

# Create writable directories
RUN mkdir -p logs && chown -R appuser:appgroup /app

USER appuser

EXPOSE 10000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:${PORT:-10000}/api/health || exit 1

CMD ["node", "dist/main"]
