# Task: Family ID Service Implementation (Feature 1: Family ID System)

## Agent: Main Agent
## Status: Completed

## Summary

Implemented the Family ID System (Feature 1) for the Daxelo-Kinrel NestJS backend. This adds globally unique, human-readable Family IDs in the format `KIN-AB12CD34` that make it easy for users to share and join families.

## Files Created

1. **`/home/z/my-project/server/src/modules/families/dto/join-family.dto.ts`**
   - `JoinFamilyDto` with `familyId` (regex validated: `KIN-[A-Z0-9]{8}`) and optional `role` (`admin|member|viewer`)
   - `SearchFamilyDto` with `familyId` (same regex validation)

2. **`/home/z/my-project/server/src/modules/families/family-id.service.ts`**
   - `FamilyIdService` with full implementation:
     - `generateFamilyId()` — Uses `crypto.randomBytes()` for cryptographic randomness, retries up to 5 times on collision
     - `findByFamilyId(familyId)` — Case-insensitive search via uppercase normalization
     - `joinByFamilyId(userId, familyId, role)` — Full validation, auto-creates Person record, increments member count, emits WebSocket events
     - `isValidFamilyId(familyId)` — Regex validation `/^KIN-[A-Z0-9]{8}$/`
     - `getOrCreateFamilyId(familyInternalId)` — Migration helper for families created before this feature

3. **`/home/z/my-project/server/src/modules/families/family-id.controller.ts`**
   - `FamilyIdController` with 3 REST endpoints:
     - `POST /families/family-id/search` — Rate limited to 20 req/min
     - `POST /families/family-id/join` — Rate limited to 5 req/min
     - `GET /families/:familyId/family-id` — Get Family ID for a family (auto-generates if missing)
   - All endpoints protected with `JwtAuthGuard`
   - DTO validation with class-validator decorators

## Files Modified

1. **`/home/z/my-project/server/prisma/schema.prisma`**
   - Added `kinFamilyId String? @unique` field to Family model
   - Added `@@index([kinFamilyId])` for fast lookups
   - Removed confusing pre-existing `familyId` field that was causing TypeScript errors

2. **`/home/z/my-project/server/src/modules/families/families.module.ts`**
   - Added `FamilyIdController` and `FamilyIdService` to module
   - Imported `GatewayModule` for WebSocket event emission

3. **`/home/z/my-project/server/src/modules/families/families.service.ts`**
   - Injected `FamilyIdService` via `forwardRef` to avoid circular dependency
   - Updated `create()` to auto-generate `kinFamilyId` when creating a family
   - Updated `formatFamily()` to include `kinFamilyId` in the response
   - Updated `findAll()` to include `kinFamilyId` in the select query

## Key Design Decisions

- **Field name `kinFamilyId`**: Chosen over `familyId` to avoid confusion with the foreign key `familyId` used in related models (FamilyMember, Person, etc.)
- **Nullable field (`String?`)**: The `kinFamilyId` field is nullable to support existing families created before this feature. The `getOrCreateFamilyId()` method handles migration.
- **Pre-generation outside transaction**: The Family ID is generated before the database transaction to avoid holding transaction locks during the random generation and collision check.
- **Case-insensitive search**: Input is normalized to uppercase before querying, ensuring `kin-ab12cd34` matches `KIN-AB12CD34`.
- **WebSocket events**: When a user joins a family via Family ID, three events are emitted: `person:created`, `member:joined`, and `graph:updated` (debounced).
- **Rate limiting**: Join endpoint is limited to 5 req/min to prevent spam; search is limited to 20 req/min to prevent enumeration attacks.

## TypeScript Verification

All new and modified files pass TypeScript type-checking with the server's tsconfig. The only remaining errors are pre-existing in `graph-engine.service.ts`.
