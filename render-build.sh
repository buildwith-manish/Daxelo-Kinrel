#!/usr/bin/env bash
# Render build script — runs from repo root
set -euo pipefail

echo "=== Render Build Script ==="
echo "Node version: $(node -v)"
echo "npm version: $(npm -v)"
echo "Working directory: $(pwd)"
echo ""

echo "=== Installing server dependencies ==="
cd server
npm ci --legacy-peer-deps 2>&1

echo ""
echo "=== Generating Prisma client ==="
npx prisma generate 2>&1

echo ""
echo "=== Building NestJS app ==="
npm run build 2>&1

echo ""
echo "=== Build complete! ==="
ls -la dist/
