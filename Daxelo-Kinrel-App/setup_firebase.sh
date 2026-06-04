#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# KINREL — Firebase Crashlytics Setup Script
#
# Run this ONCE on your local machine to configure Firebase.
# This script handles all the interactive setup that can't be
# done in CI/CD.
#
# Prerequisites:
#   - Node.js installed (for firebase-tools)
#   - Flutter SDK installed
#   - A Firebase project named "daxelo-kinrel" already created
#     at https://console.firebase.google.com
# ═══════════════════════════════════════════════════════════════

set -e

echo "🔥 Daxelo-KinRel — Firebase Crashlytics Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Step 1: Install Firebase CLI ─────────────────────────────
echo "📦 Step 1: Installing Firebase CLI..."
npm install -g firebase-tools

# ── Step 2: Login to Firebase ────────────────────────────────
echo ""
echo "🔐 Step 2: Logging into Firebase (opens browser)..."
firebase login

# ── Step 3: Install FlutterFire CLI ──────────────────────────
echo ""
echo "📦 Step 3: Installing FlutterFire CLI..."
dart pub global activate flutterfire_cli

# ── Step 4: Configure FlutterFire ────────────────────────────
echo ""
echo "⚙️  Step 4: Running flutterfire configure..."
echo "   Select your Firebase project: daxelo-kinrel"
echo "   Select platforms: android, ios"
echo ""
cd "$(dirname "$0")"
flutterfire configure --project=daxelo-kinrel --platforms=android,ios

# ── Step 5: Verify ───────────────────────────────────────────
echo ""
echo "✅ Verification:"
ERRORS=0

if [ -f "android/app/google-services.json" ]; then
    echo "  ✅ google-services.json found"
else
    echo "  ❌ google-services.json NOT found"
    ERRORS=$((ERRORS + 1))
fi

if [ -f "ios/Runner/GoogleService-Info.plist" ]; then
    echo "  ✅ GoogleService-Info.plist found"
else
    echo "  ❌ GoogleService-Info.plist NOT found"
    ERRORS=$((ERRORS + 1))
fi

if [ -f "lib/firebase_options.dart" ]; then
    echo "  ✅ firebase_options.dart generated"
else
    echo "  ❌ firebase_options.dart NOT generated"
    ERRORS=$((ERRORS + 1))
fi

echo ""
if [ $ERRORS -eq 0 ]; then
    echo "🎉 Firebase Crashlytics setup complete!"
    echo ""
    echo "   Next steps:"
    echo "   1. Run: flutter run"
    echo "   2. Test crash: tap the Test Crash button in debug menu"
    echo "   3. Check Firebase Console → Crashlytics (within 5 min)"
    echo ""
    echo "   ⚠️  DO NOT commit google-services.json or GoogleService-Info.plist"
    echo "       They are in .gitignore — CI/CD should inject them via secrets."
else
    echo "❌ Setup incomplete — $ERRORS file(s) missing"
    echo "   Re-run: flutterfire configure --project=daxelo-kinrel"
fi
