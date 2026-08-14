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
