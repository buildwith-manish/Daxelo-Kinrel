#!/bin/bash
set -e

echo "🚀 Daxelo Kinrel — Dev Setup"
echo "=============================="
echo ""

# ── Check prerequisites ────────────────────────────────────────
check_command() {
  if ! command -v "$1" &> /dev/null; then
    echo "❌ $1 is not installed. Please install it first."
    echo "   $2"
    exit 1
  fi
  echo "✅ $1 found"
}

check_command node "https://nodejs.org/"
check_command npm "Comes with Node.js"
check_command flutter "https://flutter.dev/docs/get-dev-started"
check_command git "https://git-scm.com/"

echo ""

# ── Backend ─────────────────────────────────────────────────────
echo "📦 Setting up backend..."
cd server

if [ ! -f .env ]; then
  cp ../.env.example .env
  echo "⚠️  .env created from .env.example"
  echo "   Please fill in all values in server/.env, then press Enter to continue..."
  read -r
else
  echo "✅ .env already exists"
fi

npm install
npx prisma generate
npx prisma migrate dev

# Optional: seed demo data
echo ""
read -p "Seed demo data? (y/N): " -n 1 -r SEED
echo ""
if [[ $SEED =~ ^[Yy]$ ]]; then
  npx prisma db seed 2>/dev/null || echo "⚠️  Seed script not configured yet — skipping"
fi

cd ..
echo "✅ Backend setup complete"
echo ""

# ── Flutter App ─────────────────────────────────────────────────
echo "📱 Setting up Flutter app..."
cd Daxelo-Kinrel-App

if [ ! -f .env ]; then
  cp .env.example .env
  echo "⚠️  .env created from .env.example"
  echo "   Please fill in all values in Daxelo-Kinrel-App/.env, then press Enter to continue..."
  read -r
else
  echo "✅ .env already exists"
fi

flutter pub get
dart run build_runner build --delete-conflicting-outputs

cd ..
echo "✅ Flutter app setup complete"
echo ""

# ── Done ────────────────────────────────────────────────────────
echo "=============================="
echo "✅ Setup complete!"
echo ""
echo "Run backend:  cd server && npm run start:dev"
echo "Run app:      cd Daxelo-Kinrel-App && flutter run"
echo ""
echo "API docs:     http://localhost:3000/api/docs (if Swagger enabled)"
