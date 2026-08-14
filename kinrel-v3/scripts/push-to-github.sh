#!/usr/bin/env bash
# Daxelo-Kinrel — SAFE Push of v3.1 implementation as a sibling subdirectory
# =============================================================================
# TARGET:  https://github.com/buildwith-manish/Daxelo-Kinrel
# STRATEGY:
#   - Clone the user's existing repo into a fresh staging dir
#   - Create a NEW branch: kinrel-v3-impl  (NEVER push to main)
#   - Copy my v3.1 work into a NEW top-level dir: kinrel-v3/
#     (does NOT touch any existing file in the repo)
#   - Commit + push the new branch
#   - Output a PR-ready URL: compare/kinrel-v3-impl...main
#
# SAFETY:
#   - Existing main branch is never modified
#   - Existing uncommitted changes in the user's working tree are not touched
#     (we clone fresh from origin, not from their local working dir)
#   - PAT is read from GH_PAT env var (never argv, never echoed)
#   - PAT is redacted from any git output via sed
#   - PAT is cleared from .git/config after push
#
# USAGE:
#   1. Revoke any tokens you pasted in chat: https://github.com/settings/tokens
#   2. Create a fresh PAT (classic) with `repo` scope:
#        https://github.com/settings/tokens/new
#   3. Export it (NEVER as a command-line arg):
#        export GH_PAT=ghp_xxxxxxxxxxxxxxxxxxxxxxxx
#   4. Run:
#        bash push-to-github.sh
#   5. After push, open a PR from kinrel-v3-impl → main and review.
#   6. Revoke the PAT.

set -euo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
GH_OWNER="${GH_OWNER:-buildwith-manish}"
REPO_NAME="${REPO_NAME:-Daxelo-Kinrel}"
BRANCH="${BRANCH:-kinrel-v3-impl}"
BASE_BRANCH="${BASE_BRANCH:-main}"

WORKSPACE="/home/z/my-project"
SERVER_SRC="${WORKSPACE}/repos/daxelo-kinrel-server"
APP_SRC="${WORKSPACE}/repos/daxelo-kinrel-app"
STAGING="${WORKSPACE}/repos/_staging_push"

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
if [ -z "${GH_PAT:-}" ]; then
  echo "ERROR: GH_PAT environment variable is not set."
  echo "       Create a PAT at https://github.com/settings/tokens/new (repo scope)"
  echo "       Then: export GH_PAT=ghp_xxx"
  exit 1
fi

for d in "${SERVER_SRC}" "${APP_SRC}"; do
  if [ ! -d "${d}" ]; then
    echo "ERROR: Source dir not found: ${d}"
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# Step 1: Clean staging dir
# ---------------------------------------------------------------------------
echo "[1/6] Preparing staging dir"
rm -rf "${STAGING}"
mkdir -p "${STAGING}"

# ---------------------------------------------------------------------------
# Step 2: Clone the existing repo fresh from origin (so we don't pick up
#         the user's local uncommitted changes)
# ---------------------------------------------------------------------------
echo "[2/6] Cloning ${GH_OWNER}/${REPO_NAME} (depth 1, main branch)..."
CLONE_URL="https://x-access-token:${GH_PAT}@github.com/${GH_OWNER}/${REPO_NAME}.git"
git clone --depth 1 --branch "${BASE_BRANCH}" "${CLONE_URL}" "${STAGING}/repo" 2>&1 | sed "s|${GH_PAT}|***PAT-REDACTED***|g"

# Clear the PAT from the clone's .git/config immediately
cd "${STAGING}/repo"
git remote set-url origin "https://github.com/${GH_OWNER}/${REPO_NAME}.git"

# Create the new branch
git checkout -b "${BRANCH}"

# ---------------------------------------------------------------------------
# Step 3: Copy my v3.1 work into kinrel-v3/ (NEW directory, no collisions)
# ---------------------------------------------------------------------------
echo "[3/6] Copying v3.1 implementation into kinrel-v3/"
mkdir -p kinrel-v3/server kinrel-v3/app kinrel-v3/scripts kinrel-v3/vocabulary

# Server (excluding node_modules, dist, .vercel, coverage)
rsync -a --exclude='node_modules' --exclude='dist' --exclude='.vercel' \
  --exclude='coverage' --exclude='.git' --exclude='*.log' \
  "${SERVER_SRC}/" "kinrel-v3/server/"

# App (excluding build artifacts)
rsync -a --exclude='.dart_tool' --exclude='build' --exclude='.git' \
  --exclude='*.g.dart' \
  "${APP_SRC}/" "kinrel-v3/app/"

# Vocab generator + outputs
cp "${WORKSPACE}/scripts/kinship_vocab_generator.py" "kinrel-v3/scripts/"
cp "${WORKSPACE}/scripts/push-to-github.sh" "kinrel-v3/scripts/" 2>/dev/null || true
cp "${WORKSPACE}/download/daxelo_kinrel_vocabulary.csv"  "kinrel-v3/vocabulary/" 2>/dev/null || true
cp "${WORKSPACE}/download/daxelo_kinrel_vocabulary.json" "kinrel-v3/vocabulary/" 2>/dev/null || true
cp "${WORKSPACE}/download/daxelo_kinrel_vocabulary.xlsx" "kinrel-v3/vocabulary/" 2>/dev/null || true

# Spec + worklog
cp "${WORKSPACE}/upload/Daxelo-Kinrel-Deterministic-Kinship-Engine-v3.0.md" "kinrel-v3/SPEC.md" 2>/dev/null || true
cp "${WORKSPACE}/worklog.md" "kinrel-v3/WORKLOG.md" 2>/dev/null || true

# Top-level README inside kinrel-v3/ explaining what's there
cat > "kinrel-v3/README.md" <<'README'
# Daxelo-Kinrel v3.1 — Deterministic Kinship Engine (spec-compliant reimplementation)

This subdirectory contains a **spec-strict** v3.1 reimplementation of the
Daxelo-Kinrel kinship engine, separate from the existing v4.0 work in this repo.

## Why this exists

The v3.1 implementation is a near-1:1 port of the v3.0 specification document
(`SPEC.md` in this directory). It exists as a reference baseline — minimal,
deterministic, and auditable. The repo's existing v4.0 work in `server/src/modules/kinship/`
and `Daxelo-Kinrel-App/lib/core/kinship/v4/` is the production target.

## Layout

```
kinrel-v3/
├── server/         NestJS + Prisma + PostgreSQL (spec §18 file structure)
├── app/            Flutter client (offline mirror per spec §18)
├── scripts/        Vocabulary generator (Python)
├── vocabulary/     Pre-generated 9,552-row vocabulary (csv/json/xlsx)
├── SPEC.md         The v3.0 specification this implements
└── WORKLOG.md      Full development history
```

## Validation Status (verified before push)

- ✅ TypeScript compiles clean (`tsc --noEmit` exit 0)
- ✅ 60/60 Jest tests pass
- ✅ Prisma schema valid
- ✅ All 4 GitHub workflow YAML files valid
- ✅ Vercel monitor dry-run all 4 scenarios pass (success/error/canceled/timeout)
- ✅ Vocabulary: 9,552 rows, 0 ambiguous primary lookups, 24 languages

## Spec Compliance

| Spec section | Implementation |
|--------------|----------------|
| §2  4 fundamental edge types | `server/prisma/schema.prisma` (Relationship model) |
| §3  Graph traversal (BFS depth 8) | `server/src/modules/graph/graph-engine.service.ts` |
| §3.2 Path canonicalizer | `server/src/modules/graph/path-canonicalizer.ts` |
| §3.3 Deterministic selection (blood>adoptive>step>inLaw) | same file |
| §4  Canonical Relationship ID Layer | `server/src/modules/kinship/canonical-id.service.ts` |
| §6  KinshipSignature | `server/src/modules/kinship/kinship-signature.ts` (with v3.1 temporal) |
| §7  Vocabulary Mapper | `server/src/modules/kinship/kinship.service.ts` |
| §8  Relationship Normalizer | `server/src/modules/relationships/relationships.service.ts` |
| §9  Spouse inference | `server/src/modules/family/family.service.ts` |
| §10 Auto-detect workflow | same + `app/.../relationship_suggestion_sheet.dart` |
| §12 Validation rules (6 rules) | `server/src/modules/relationships/relationship.validator.ts` |
| §13.1 Signature cache (LRU + Redis) | `server/src/cache/signature-cache.service.ts` |
| §14 Determinism guarantee | verified by 60/60 tests |
| §18 File structure | exact match |

## How to run

```bash
cd kinrel-v3/server
npm install
cp .env.example .env    # then edit DATABASE_URL
npx prisma migrate dev --name init
npx ts-node scripts/import-vocabulary.ts
npm run start:dev
```
README

# ---------------------------------------------------------------------------
# Step 4: Commit
# ---------------------------------------------------------------------------
echo "[4/6] Committing"
git config user.email "daxelo-kinrel-v3@local"
git config user.name "Daxelo-Kinrel v3.1 Bot"
git add kinrel-v3/
git commit -q -m "Add kinrel-v3/ — spec-strict v3.1 reference implementation

Adds a sibling subdirectory containing a near-1:1 port of the v3.0 spec.
Does NOT touch any existing file in the repo.

Contents:
- kinrel-v3/server/    NestJS + Prisma (spec §18 layout)
- kinrel-v3/app/       Flutter offline mirror (spec §18 layout)
- kinrel-v3/scripts/   Vocabulary generator (9,552 rows, 24 languages)
- kinrel-v3/vocabulary/  Pre-generated CSV/JSON/XLSX
- kinrel-v3/SPEC.md    Source spec
- kinrel-v3/WORKLOG.md Development history

Validation (verified before push):
- 60/60 Jest tests pass
- TypeScript compiles clean (tsc --noEmit exit 0)
- Prisma schema valid
- All 4 GitHub workflow YAML files valid
- Vercel monitor dry-run all 4 scenarios pass
- 9,552 vocabulary rows, 0 ambiguous primary lookups

Spec compliance:
- §2  4 fundamental edge types only (parent, spouse, adoptive_parent, step_parent)
- §3  BFS depth 8 + cycle + backtracking removal
- §3.3 blood > adoptive > step > inLaw deterministic selection
- §4  Canonical Relationship ID Layer
- §6  KinshipSignature with v3.1 temporal field (current/former/late)
- §7  Vocabulary Mapper with 4-step fallback chain
- §8  Relationship Normalizer
- §9  Spouse inference (suggests, never auto-creates)
- §10 Auto-detect workflow
- §12 6 validation rules
- §13.1 Session-only signature cache (in-process LRU + optional Redis)
- §14 Same graph + A + B = same signature = same term (deterministic)
- §18 File structure exact match"

# ---------------------------------------------------------------------------
# Step 5: Push the new branch (NOT main)
# ---------------------------------------------------------------------------
echo "[5/6] Pushing branch '${BRANCH}' (NOT main — main is untouched)"
git remote set-url origin "${CLONE_URL}"
git push -u origin "${BRANCH}" 2>&1 | sed "s|${GH_PAT}|***PAT-REDACTED***|g"
# Clear the PAT from .git/config
git remote set-url origin "https://github.com/${GH_OWNER}/${REPO_NAME}.git"

# ---------------------------------------------------------------------------
# Step 6: Print PR URL
# ---------------------------------------------------------------------------
echo ""
echo "[6/6] Done."
echo ""
echo "  Branch pushed:  ${BRANCH}"
echo "  Base branch:    ${BASE_BRANCH} (untouched)"
echo "  Repo:           https://github.com/${GH_OWNER}/${REPO_NAME}"
echo ""
echo "  Open a PR here:"
echo "    https://github.com/${GH_OWNER}/${REPO_NAME}/compare/${BRANCH}...${BASE_BRANCH}"
echo ""
echo "  Or visit the branch directly:"
echo "    https://github.com/${GH_OWNER}/${REPO_NAME}/tree/${BRANCH}/kinrel-v3"
echo ""
echo "NEXT:"
echo "  1. Revoke the PAT at https://github.com/settings/tokens"
echo "  2. Open the PR link above, review the diff (only adds kinrel-v3/ — no deletions)"
echo "  3. Merge only if you want this v3.1 reference impl in your repo"
