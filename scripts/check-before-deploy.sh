#!/usr/bin/env bash
# Pre-push / pre-deploy sanity check. Run from anywhere:
#   ./scripts/check-before-deploy.sh
#
# Runs the same static checks CI runs, so a red build is caught locally:
#   1. Flutter: `flutter analyze --fatal-warnings --no-fatal-infos` in Daxelo-Kinrel-App/
#      (same flags as the `Flutter Analyze` job in .github/workflows/ci.yml)
#   2. Backend: `npx tsc --noEmit` in server/
#
# Both checks always run (one failure does not hide the other). Exit code is
# non-zero if any check FAILED. If the Flutter SDK is not installed the Flutter
# check is reported as SKIPPED (loudly) rather than silently passing; set
# REQUIRE_FLUTTER=1 to treat a missing SDK as a failure instead.

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILED=0
RESULTS=()

banner() { printf '\n==> %s\n' "$1"; }

# --- 1. Flutter analyze ------------------------------------------------------
banner "Flutter analyze (Daxelo-Kinrel-App/)"
if command -v flutter >/dev/null 2>&1; then
  if (cd "$REPO_ROOT/Daxelo-Kinrel-App" && flutter analyze --fatal-warnings --no-fatal-infos); then
    RESULTS+=("PASS     flutter analyze")
  else
    RESULTS+=("FAIL     flutter analyze")
    FAILED=1
  fi
else
  echo "Flutter SDK not found on PATH (\`flutter\` command missing)."
  echo "flutter analyze was NOT run. Install Flutter (see CONTRIBUTING.md) or rely on the"
  echo "'Flutter Analyze' job in CI before merging."
  if [ "${REQUIRE_FLUTTER:-0}" = "1" ]; then
    RESULTS+=("FAIL     flutter analyze (SDK missing, REQUIRE_FLUTTER=1)")
    FAILED=1
  else
    RESULTS+=("SKIPPED  flutter analyze (Flutter SDK not installed — NOT verified)")
  fi
fi

# --- 2. Backend type-check ---------------------------------------------------
banner "TypeScript type-check (server/)"
if [ ! -x "$REPO_ROOT/server/node_modules/.bin/tsc" ]; then
  echo "server/node_modules is missing, so tsc cannot run."
  echo "Run: (cd server && npm install && npx prisma generate)"
  RESULTS+=("FAIL     tsc --noEmit (dependencies not installed)")
  FAILED=1
elif (cd "$REPO_ROOT/server" && npx --no-install tsc --noEmit); then
  RESULTS+=("PASS     tsc --noEmit")
else
  echo
  echo "Hint: if errors mention missing Prisma types (e.g. 'Property ... does not exist on"
  echo "type PrismaClient'), run \`cd server && npx prisma generate\` and retry."
  RESULTS+=("FAIL     tsc --noEmit")
  FAILED=1
fi

# --- Summary -----------------------------------------------------------------
banner "Summary"
for r in "${RESULTS[@]}"; do echo "  $r"; done
if [ "$FAILED" -ne 0 ]; then
  echo; echo "check-before-deploy: FAILED — fix the above before pushing."
  exit 1
fi
echo; echo "check-before-deploy: OK (see any SKIPPED lines above — those were not checked)."
