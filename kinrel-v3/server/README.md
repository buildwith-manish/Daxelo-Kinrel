# Daxelo-Kinrel Server — Deterministic Kinship Engine v3.1

NestJS + Prisma + PostgreSQL implementation of the Daxelo-Kinrel Deterministic Kinship Engine v3.0 spec, with the v3.1 `temporal` field extension.

## File Structure (spec §18)

```
server/src/
├── app.module.ts                              # Root NestJS module — wires all services
├── main.ts                                    # NestJS bootstrap
├── prisma/
│   └── prisma.service.ts                      # PrismaClient wrapper for DI
└── modules/
    ├── kinship/
    │   ├── kinship.service.ts                 # Vocabulary mapper (9,552 terms, spec §7)
    │   ├── kinship-signature.ts               # Signature interface + builder (spec §6)
    │   └── canonical-id.service.ts            # Canonical Relationship ID Layer (spec §4)
    ├── graph/
    │   ├── graph-engine.service.ts            # BFS traversal + signature build (spec §3.1, §5)
    │   ├── path-canonicalizer.ts              # Cycle/backtracking removal (spec §3.2, §3.3)
    │   └── graph.service.ts                   # Tree building & enriched graph
    ├── relationships/
    │   ├── relationships.service.ts           # CRUD + normalizer (spec §8, §10)
    │   └── relationship.validator.ts          # 6 validation rules (spec §12)
    └── family/
        └── family.service.ts                  # Orchestration + spouse inference (spec §9)

prisma/
└── schema.prisma                              # Person, Family, Relationship, KinshipVocabulary

scripts/
└── import-vocabulary.ts                       # CSV → PostgreSQL importer
```

## Setup

```bash
# 1. Install dependencies
pnpm install        # or npm install / yarn install

# 2. Configure database
cp .env.example .env
# Edit .env — set DATABASE_URL to your Postgres instance

# 3. Push schema to database
pnpm prisma:generate
pnpm prisma:push

# 4. Import the 9,552-row vocabulary table
pnpm import:vocab
# Output:
#   ✓ Total rows: 9552
#   ✓ Primary (variant_rank=0): 8748
#   ✓ Languages: 24

# 5. Start the server
pnpm start:dev
```

## How Determinism Works (spec §14)

```
Same Graph + Same Person A + Same Person B
    = Same Canonical Path
    = Same KinshipSignature
    = Same signatureKey
    = Same Vocabulary Row (WHERE variant_rank=0)
    = Same Kinship Term
```

Every time. No exceptions. No ML. No confidence scores.

## API Surface (FamilyService)

| Method | Purpose | Spec ref |
|--------|---------|----------|
| `createFamily(name)` | New family | — |
| `addPerson(familyId, data)` | Add a person | — |
| `createRelationship(input)` | Create fundamental edge (after validation) | §8, §12 |
| `detectRelationship(familyId, A, B, locale)` | Auto-detect workflow | §10 |
| `resolveKinshipLabel(familyId, A, B, locale)` | Get localized label for A→B | §7, §14 |
| `getTree(familyId, rootPersonId, locale)` | Build enriched tree for UI | §3 |
| `inferSpouse(familyId, A, B)` | Spouse inference (dashed line in UI) | §9 |
| `confirmSpouseInference(familyId, A, B)` | Persist inferred spouse edge | §9.2 |

## Vocabulary Mapper — Lookup Contract

```ts
// Deterministic primary lookup (spec §14)
await prisma.kinshipVocabulary.findFirst({
  where: {
    signatureKey,           // composite key from KinshipSignature
    languageCode,           // ISO 639-1
    variantRank: 0,         // primary only — alternates via resolveVariants()
  },
});

// Fallback chain (spec §7.2) handled inside KinshipService.resolveTerm():
//   1. Try without seniority
//   2. Try with genderAnchor = neutral
//   3. Try generic term (match on pathPattern only)
//   4. Compose descriptive term as last resort
```

## v3.1 — Temporal Field Extension

The `temporal` field was added as a **first-class** part of the `KinshipSignature` in v3.1. This lets the engine distinguish `ex-husband` from `husband` deterministically without any `variant_rank` fallback.

| `temporal` | Meaning | Example |
|-----------|---------|---------|
| `current` | Active relationship | "father", "wife", "brother" |
| `former` | Divorced / severed | "ex-husband", "ex-father-in-law" |
| `late` | Deceased | "late father", "late wife" |

The engine reads `temporal` from the stored edge's `EdgeTemporal` enum and propagates it into the signature. This produces distinct signatureKeys for `current` vs `former` vs `late` variants of the same path pattern.

## Adding a New Term (#9,553)

Per spec §7.1: "Adding term #5,397 requires only a new vocabulary entry. No engine changes."

```bash
# 1. Edit the generator
vim /home/z/my-project/scripts/kinship_vocab_generator.py
# Add a new add(...) call in _build_seed_concepts()

# 2. Regenerate
python3 /home/z/my-project/scripts/kinship_vocab_generator.py

# 3. Re-import
pnpm import:vocab
```

The engine code never changes.
