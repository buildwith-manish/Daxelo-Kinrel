# DAXELO-KINREL DETERMINISTIC KINSHIP ENGINE v3.0

## PRODUCTION IMPLEMENTATION PROMPT

**Objective:** Build a genealogy-grade deterministic kinship engine for Daxelo-Kinrel that derives all 5,396+ kinship terms from only four fundamental relationship edges, with zero ML, zero derived storage, and 100% deterministic behavior.

**Target Stack:** Flutter (Dart) + NestJS (TypeScript) + PostgreSQL (Prisma) + Supabase + Drift (offline SQLite) + Redis

---

## 1. CORE PRINCIPLES

1. **Store ONLY fundamental relationships.** The database is the single source of truth.
2. **Derive everything else at runtime.** No grandfather, uncle, cousin, or in-law rows in the database.
3. **100% deterministic.** Same graph + same Person A + same Person B = same result. Always.
4. **No ML / No AI / No confidence scores.** Pure graph traversal and rule-based composition.
5. **Minimal storage.** Only four edge types exist in the database.
6. **Never guess.** If the graph underdetermines a relationship, ask the user once, store the fundamental edge, then recalculate.
7. **Canonical Relationship IDs.** All colloquial, regional, and language-specific variants map to a single canonical ID before processing.

---

## 2. FUNDAMENTAL RELATIONSHIPS (Database Storage)

The `Relationship` table stores **only** these four directed edge types:

| Edge Type | Direction | Meaning |
|-----------|-----------|---------|
| `parent` | A → B | A's parent is B |
| `spouse` | A ↔ B | A and B are spouses (bidirectional) |
| `adoptive_parent` | A → B | A's adoptive parent is B |
| `step_parent` | A → B | A's step-parent is B |

**DO NOT STORE:**
- `father`, `mother` (use `parent` + Person.gender)
- `son`, `daughter` (inverse of `parent`)
- `brother`, `sister`, `half_brother`, `step_brother`
- `grandfather`, `grandmother`, `great_grandfather`
- `uncle`, `aunt`, `great_uncle`, `great_aunt`
- `nephew`, `niece`, `cousin`
- `father_in_law`, `mother_in_law`, `brother_in_law`, `sister_in_law`
- Any other derived kinship label

---

## 3. ARCHITECTURE

```
User Input Term
      ↓
Canonical Relationship ID Layer
(father/dad/appa/papa/baba → PARENT)
      ↓
Fundamental Family Graph (DB)
      ↓
Graph Traversal Engine (BFS)
      ↓
Path Canonicalizer
      ↓
Kinship Signature Builder (runtime only)
      ↓
Vocabulary Mapper (5,396+ terms)
      ↓
Relationship Normalizer
(convert detected term → fundamental edge)
      ↓
Store only fundamental edge
      ↓
Displayed Relationship
```

### 3.1 Graph Traversal Engine
- Operates **only** on fundamental stored edges.
- Uses BFS to find the shortest valid path between two persons.
- **Max traversal depth: 8** (covers great-great-great-grandparents, third cousins, and removed cousins).
- Cycle detection enabled. Never traverse a cycle.

### 3.2 Path Canonicalizer
Before signature generation:
1. Remove cycles.
2. Remove backtracking (e.g., `UP_PARENT` followed immediately by `DOWN_CHILD` on the same node).
3. Normalize equivalent paths to one canonical form.
4. Produce the **shortest valid path**.

### 3.3 Deterministic Path Selection
When multiple shortest paths of equal length exist, apply this priority:

```
blood  >  adoptive  >  step  >  inLaw
```

Example: If both a blood father path and a step-father path exist, the blood path wins. This guarantees deterministic output.

---

## 4. CANONICAL RELATIONSHIP ID LAYER (NEW)

All user-facing kinship terms, colloquial names, and regional variants must map to a **Canonical Relationship ID** before entering the engine.

### 4.1 Canonical ID Mapping

| User Input | Canonical ID |
|-----------|-------------|
| father, dad, appa, papa, baba, abba | `PARENT` |
| mother, mom, amma, mummy, maa, ummi | `PARENT` |
| husband, pati, miya | `SPOUSE` |
| wife, patni, biwi | `SPOUSE` |
| son, beta, putra | `PARENT` (inverse direction) |
| daughter, beti, putri | `PARENT` (inverse direction) |
| adoptive father | `ADOPTIVE_PARENT` |
| step mother | `STEP_PARENT` |
| grandfather, dada, nana, thatha | **DERIVED — do not store** |
| uncle, chacha, mama, kaka | **DERIVED — do not store** |
| cousin | **DERIVED — do not store** |

### 4.2 Purpose
- Makes localization trivial: add language variants without touching the engine.
- Prevents duplicate storage of the same fundamental relationship under different names.
- Enables the Relationship Normalizer to work correctly.

### 4.3 Implementation
```typescript
// Preprocessing layer before any engine call
function normalizeToCanonical(input: string, locale: string): CanonicalId {
  // Lookup in locale-specific synonym table
  // Return canonical ID
}
```

---

## 5. GRAPH TRAVERSAL PRIMITIVES

The traversal engine uses only these primitives. Derived relationships never participate in traversal.

| Primitive | Stored Edge Traversed | Direction |
|-----------|----------------------|-----------|
| `UP_PARENT` | `parent` | child → parent |
| `DOWN_CHILD` | `parent` | parent → child |
| `SPOUSE` | `spouse` | bidirectional |
| `UP_ADOPTIVE_PARENT` | `adoptive_parent` | child → adoptive parent |
| `UP_STEP_PARENT` | `step_parent` | child → step-parent |

**Forbidden primitives:** `BROTHER`, `SISTER`, `UNCLE`, `AUNT`, `COUSIN`, `GRANDFATHER` — these must always be derived.

---

## 6. CANONICAL PATH SIGNATURE

A runtime-only data structure. **Never stored. Never persisted. Never cached permanently.**

```typescript
interface KinshipSignature {
  generationDelta: number;      // -8 to +8
  pathPattern: string;          // e.g., "UP_PARENT", "UP_PARENT_UP_PARENT"
  side: 'paternal' | 'maternal' | 'none';
  consanguinity: 'blood' | 'half' | 'step' | 'adoptive' | 'inLaw';
  genderAnchor: 'male' | 'female' | 'neutral';
  seniority: 'elder' | 'younger' | 'twin' | 'none';
  removal: number;              // for "once removed", "twice removed"
  doubleKinship: boolean;       // true for double first cousins, etc.
}
```

### 6.1 Path Pattern Grammar
Path patterns are constructed by joining traversal primitives with underscores.

| Relationship | Path Pattern |
|-------------|-------------|
| Father | `UP_PARENT` |
| Grandfather | `UP_PARENT_UP_PARENT` |
| Uncle | `UP_PARENT_DOWN_CHILD` |
| Brother | `UP_PARENT_DOWN_CHILD` |
| Cousin | `UP_PARENT_UP_PARENT_DOWN_CHILD_DOWN_CHILD` |
| Father-in-law | `SPOUSE_UP_PARENT` |
| Nephew | `UP_PARENT_DOWN_CHILD_DOWN_CHILD` |
| Great-uncle | `UP_PARENT_UP_PARENT_DOWN_CHILD` |

### 6.2 Signature Examples

| Relationship | Path | Signature |
|-------------|------|-----------|
| Father | `UP_PARENT` | gen: -1, pattern: `UP_PARENT`, side: `paternal`, gender: `male` |
| Mother | `UP_PARENT` | gen: -1, pattern: `UP_PARENT`, side: `maternal`, gender: `female` |
| Grandfather | `UP_PARENT_UP_PARENT` | gen: -2, pattern: `UP_PARENT_UP_PARENT`, side: `paternal`, gender: `male` |
| Uncle | `UP_PARENT_DOWN_CHILD` | gen: -1, pattern: `UP_PARENT_DOWN_CHILD`, side: `paternal`, gender: `male` |
| Brother | `UP_PARENT_DOWN_CHILD` | gen: 0, pattern: `UP_PARENT_DOWN_CHILD`, consanguinity: `blood` |
| Cousin | `UP_PARENT_UP_PARENT_DOWN_CHILD_DOWN_CHILD` | gen: 0, pattern: `UP_PARENT_UP_PARENT_DOWN_CHILD_DOWN_CHILD`, removal: 0 |
| Father-in-law | `SPOUSE_UP_PARENT` | gen: -1, pattern: `SPOUSE_UP_PARENT`, consanguinity: `inLaw` |

### 6.3 Side Detection
- `side` is determined by the **first `UP_PARENT` link** traversed from the starting person.
- Father branch → `paternal`
- Mother branch → `maternal`
- No parent branch (pure `SPOUSE` traversal) → `none`

### 6.4 Sibling Consanguinity Detection
When the path pattern is `UP_PARENT_DOWN_CHILD`:
1. Find all parents of Person A.
2. Find all parents of Person B.
3. Count shared parents:
   - `sharedParents >= 2` → `consanguinity: 'blood'` (full sibling)
   - `sharedParents === 1` → `consanguinity: 'half'` (half sibling)
   - `sharedParents === 0` AND parents are married → `consanguinity: 'step'` (step sibling)

### 6.5 Cousin Detection
Derived from:
- `generationDelta`
- `removal` = |generationDelta| when equal UP_PARENT and DOWN_CHILD counts exist
- `side` (paternal/maternal)
- `doubleKinship` flag when multiple valid paths exist

Examples:
- First cousin: 2 UP + 2 DOWN, removal = 0
- First cousin once removed: 2 UP + 3 DOWN, removal = 1
- Second cousin: 3 UP + 3 DOWN, removal = 0
- Double first cousin: `doubleKinship: true`

---

## 7. VOCABULARY MAPPER

The graph engine **never returns relationship names**. It returns only `KinshipSignature` objects.

```
KinshipSignature
      ↓
Vocabulary Mapper
      ↓
Kinship Term (from 5,396+ database)
```

### 7.1 Mapping Rules
- The mapper looks up the signature in the vocabulary database.
- Adding term #5,397 requires **only** a new vocabulary entry. **No engine changes.**
- The engine knows nothing about individual vocabulary terms.

### 7.2 Fallback Chain
If exact signature match fails:
1. Try without `seniority`
2. Try with `genderAnchor: 'neutral'`
3. Try generic term
4. Compose descriptive term as last resort

Example:
- If birth order exists → `Elder Brother`
- If birth order missing → `Brother`

---

## 8. RELATIONSHIP NORMALIZER

This is the bridge between user-facing kinship terms and fundamental storage.

```
Detected Term (e.g., "wife")
      ↓
Canonical ID (e.g., "SPOUSE")
      ↓
Relationship Normalizer
      ↓
Fundamental Edge (e.g., "spouse")
      ↓
Store in Database
```

### 8.1 Normalization Rules

| Detected Term | Canonical ID | Fundamental Edge Stored |
|--------------|-------------|------------------------|
| Father, Dad, Appa, Papa | `PARENT` | `parent` |
| Son, Daughter, Beta, Beti | `PARENT` | `parent` (inverse direction) |
| Husband, Wife, Pati, Patni | `SPOUSE` | `spouse` |
| Adoptive Father | `ADOPTIVE_PARENT` | `adoptive_parent` |
| Step Mother | `STEP_PARENT` | `step_parent` |
| Grandfather, Uncle, Cousin | **DERIVED** | **Do not store.** Ask user for missing fundamental edge. |

### 8.2 Critical Rule
If the auto-detection engine returns a derived term (e.g., "uncle"), the normalizer must trace back to the **missing fundamental edge** that would complete the graph, ask the user to confirm that edge, and store only the fundamental edge.

---

## 9. SPOUSE INFERENCE

### 9.1 Detection Rule
If Person A and Person B are both parents of the same child, the system **suggests** a spouse relationship.

### 9.2 Behavior
- **Do NOT auto-create permanently without user confirmation.**
- Show as **inferred suggestion** (dashed line in UI).
- If user confirms: create `spouse` edge with `isInferred: false`.
- If user declines: do not create. No edge stored.
- If user takes no action: show dashed line but do not persist as stored edge (or store as `isInferred: true` with option to confirm/remove later).

### 9.3 Edge Cases Handled
- Divorced parents (user can decline)
- Co-parents who are not spouses (user can decline)
- Donors/guardians (user can decline)
- Adoption (handled by `adoptive_parent` edge)

---

## 10. AUTO-DETECTION WORKFLOW

```
User: Long Press Node A
  ↓
User: Tap "Relate to Another Person"
  ↓
User: Tap Node B
  ↓
System: Analyze existing graph
  ↓
System: Build shortest path (BFS, max depth 8)
  ↓
System: Build KinshipSignature
  ↓
System: Resolve term via Vocabulary Mapper
  ↓
System: Normalize to Canonical ID
  ↓
System: Normalize to fundamental edge
  ↓
System: Show detected relationship to user
  ↓
User: Confirms
  ↓
System: Create fundamental edge in database
  ↓
System: Invalidate signature cache
  ↓
System: Recalculate all derived labels
  ↓
System: Refresh graph UI
```

**UI Requirements:**
- No repeated node pickers.
- No duplicate confirmation screens.
- If auto-detection succeeds: show "Detected: [Term]" with Confirm button.
- If auto-detection fails (insufficient graph info): show manual picker with only fundamental options (`parent`, `spouse`, `adoptive_parent`, `step_parent`).

---

## 11. INVERSE RELATIONSHIP RESOLUTION

Every stored fundamental edge has a logical inverse for traversal purposes. These inverses are **computed in memory**, not stored as duplicate database rows.

| Stored Edge | Traversal Inverse |
|-------------|-------------------|
| `parent` (A→B) | `child` (B→A) |
| `spouse` (A→B) | `spouse` (B→A) |
| `adoptive_parent` (A→B) | `adoptive_child` (B→A) |
| `step_parent` (A→B) | `step_child` (B→A) |

The inverse uses the target person's gender to resolve gender-specific terms:
- `parent` inverse → `son` or `daughter`
- `child` inverse → `father` or `mother`

---

## 12. VALIDATION RULES

Before creating any relationship:

1. **Reject self-relationships.** A person cannot relate to themselves.
2. **Reject duplicate edges.** No two identical fundamental edges between the same pair.
3. **Reject circular ancestry.** If A is an ancestor of B, B cannot be a parent of A.
4. **Reject invalid spouse relationships.** Cannot marry an ancestor or descendant.
5. **Reject contradictory relationships.** If A is already B's parent, A cannot be B's spouse.
6. **Preserve existing valid relationships.** Never overwrite confirmed data automatically.

---

## 13. CACHING

### 13.1 Session-Only Signature Cache
```
Key:   "familyId:personAId:personBId"
Value: KinshipSignature
```

**Rules:**
- In-memory only. **Never persist.**
- Use targeted invalidation: when Person X is mutated, delete only cache entries containing X.
- Do NOT flush the entire cache on every graph change.
- LRU eviction after 1,000 entries per family.

### 13.2 Graph Adjacency Cache
- Cache the built adjacency list for 60 seconds.
- Invalidate on any relationship mutation.

---

## 14. DETERMINISM GUARANTEE

The following must always be true:

```
Same Graph
+
Same Person A
+
Same Person B
=
Same Canonical Path
+
Same KinshipSignature
+
Same Kinship Term
```

**Every time. No exceptions.**

- No randomness.
- No confidence scores.
- No probabilities.
- No AI predictions.
- No ML.
- No guessing.

---

## 15. PERFORMANCE TARGETS

| Metric | Target |
|--------|--------|
| Members per family | 10,000+ |
| Edges per family | 50,000+ |
| Relationship resolution (cached) | < 10ms |
| Relationship resolution (uncached) | < 50ms |
| Graph build | < 200ms |
| Tree render | < 100ms |

---

## 16. MIGRATION STRATEGY (PHASED)

**DO NOT delete derived relationships immediately.**

### Phase A: Parallel Build
- Keep the current system running.
- Build the new deterministic engine alongside.
- The new engine reads from the same database but ignores derived rows.

### Phase B: Comparison
- Run both engines in parallel.
- Compare outputs for all families.
- Fix discrepancies.

### Phase C: Gradual Cutover
- Migrate one family at a time.
- Convert derived edges to fundamental edges where possible.
- Delete derived edges only after verification.

### Phase D: Cleanup
- Remove old derived relationship rows.
- Drop deprecated code paths.

---

## 17. EXAMPLE SCENARIOS

### Example 1: Father + Mother → Spouse
**Graph:**
```
You
├── parent → Ravi (gender: male)
└── parent → Priya (gender: female)
```

**Action:** User relates Ravi → Priya.

**System:**
1. Traverses: Ravi is parent of You. Priya is parent of You.
2. Both share child = You.
3. Suggests: `spouse` relationship.
4. User confirms.
5. Stores: `Ravi → Priya = spouse`.
6. Derives: Ravi = Husband of Priya. Priya = Wife of Ravi.

### Example 2: Grandparent Derivation
**Graph:**
```
You
└── parent → Ravi
    └── parent → Arun
```

**Action:** View family tree.

**System:**
1. Path from You to Arun: `UP_PARENT_UP_PARENT`.
2. Signature: gen: -2, pattern: `UP_PARENT_UP_PARENT`, side: `paternal`, gender: `male`.
3. Vocabulary maps to: `Grandfather` (English), `दादा` (Hindi).
4. **No database row created.** Displayed at runtime only.

### Example 3: Sibling Derivation
**Graph:**
```
Ravi
├── parent → Manish
└── parent → Rahul
```

**System:**
1. Path Manish → Rahul: `UP_PARENT_DOWN_CHILD`.
2. Shared parents: [Ravi] = 1.
3. Consanguinity: `half`.
4. If Rahul is male: `Half Brother`.
5. **No database row created.**

### Example 4: Canonical ID Layer
**User Input:** "Appa" (Tamil for Father)

**System:**
1. Canonical ID Layer: "Appa" → `PARENT`
2. Engine processes as `PARENT` canonical ID.
3. Signature built normally.
4. Vocabulary maps to localized display: `Appa` (Tamil UI), `Father` (English UI).

---

## 18. FILE STRUCTURE (RECOMMENDED)

```
server/src/modules/
├── kinship/
│   ├── kinship.service.ts              # Vocabulary mapper (5,396+ terms)
│   ├── kinship-signature.ts            # Signature interface & builder
│   └── canonical-id.service.ts         # Canonical Relationship ID Layer
├── graph/
│   ├── graph-engine.service.ts         # BFS traversal & path finding
│   ├── path-canonicalizer.ts           # Path normalization & cycle removal
│   └── graph.service.ts                # Tree building & enriched graph
├── relationships/
│   ├── relationships.service.ts        # CRUD, validation, normalizer
│   └── relationship.validator.ts       # Cycle, duplicate, contradiction checks
└── family/
    └── family.service.ts               # Orchestration layer

Daxelo-Kinrel-App/lib/
├── core/
│   └── services/
│       └── relationship_engine.dart    # Flutter-side engine mirror
├── data/
│   └── drift/
│       └── app_database.dart           # Offline schema (4 edge types only)
└── features/
    └── family/
        └── presentation/
            └── widgets/
                └── relationship_suggestion_sheet.dart
```

---

## 19. FINAL GOAL

The system must derive **all 5,396+ kinship terms** from only:

- `parent`
- `spouse`
- `adoptive_parent`
- `step_parent`

Using:
- **Canonical Relationship ID Layer** (localization & normalization)
- **Graph Traversal** (BFS, depth 8)
- **Path Canonicalization** (cycle removal, backtracking removal)
- **Kinship Signature** (runtime-only structured data)
- **Vocabulary Mapping** (5,396+ terms, zero engine changes for new terms)
- **Relationship Normalization** (detected term → fundamental edge)

With **deterministic results**, **minimal storage**, **no ML**, and **automatic relationship detection**.
