#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
# register-demo.sh — Register demo users via the NestJS API
# ═══════════════════════════════════════════════════════════════════════
# Run this AFTER the server is running on port 3001
# Usage:  bash scripts/register-demo.sh
# ═══════════════════════════════════════════════════════════════════════

BASE_URL="http://localhost:3001/api"

echo "📝 Registering demo users..."
echo ""

# ── Demo User ────────────────────────────────────────────────────────
echo "1. Registering Demo User (demo@kinrel.com)..."
DEMO_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/register" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Demo User",
    "email": "demo@kinrel.com",
    "password": "Demo@1234"
  }')

if echo "$DEMO_RESPONSE" | grep -q '"id"'; then
  echo "   ✅ Demo User registered successfully!"
else
  echo "   ⚠️  Response: $DEMO_RESPONSE"
fi

echo ""

# ── Admin User ───────────────────────────────────────────────────────
echo "2. Registering Admin User (admin@kinrel.com)..."
ADMIN_RESPONSE=$(curl -s -X POST "$BASE_URL/auth/register" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Admin User",
    "email": "admin@kinrel.com",
    "password": "Admin@1234"
  }')

if echo "$ADMIN_RESPONSE" | grep -q '"id"'; then
  echo "   ✅ Admin User registered successfully!"
else
  echo "   ⚠️  Response: $ADMIN_RESPONSE"
fi

echo ""
echo "══════════════════════════════════════════════"
echo "📋 Demo Login Credentials:"
echo ""
echo "  👤 Demo User:"
echo "     Email:    demo@kinrel.com"
echo "     Password: Demo@1234"
echo ""
echo "  🛡️  Admin User:"
echo "     Email:    admin@kinrel.com"
echo "     Password: Admin@1234"
echo "══════════════════════════════════════════════"
