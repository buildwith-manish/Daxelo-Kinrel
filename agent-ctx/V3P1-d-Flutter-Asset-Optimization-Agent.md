# V3P1-d: Flutter Asset Optimization Agent

## Task
V3 Phase 1 — NEW-01: Move 165MB of JSON kinship data off-bundle to allow the app to be published to the Play Store (100MB hard limit).

## Work Completed

### Flutter App Changes

1. **kinship_loader_service.dart** — Completely rewritten to support download-on-demand:
   - `loadGlobalKinshipData(cultureKey)` — downloads from `/v1/kinship/data/:cultureKey` via Dio
   - 3-tier caching: memory → disk (path_provider) → network
   - Handles ResponseEnvelopeInterceptor wrapping (extracts `data` field if present)
   - Corrupted disk cache detection and auto-recovery
   - `isCached()`, `clearCache()` for cache management
   - Legacy `search()` and `getLanguages()` methods preserved for backward compatibility

2. **global_kinship_service.dart** — Modified to use loader instead of rootBundle:
   - Added `KinshipLoaderService? _loader` constructor parameter
   - `loadCulture()` now uses loader for server download when available
   - Falls back to `rootBundle.loadString()` when loader is null (legacy/testing)
   - Removed `dataAssetPath != null` check — only checks `hasDataFile` now

3. **global_kinship_provider.dart** — Wired loader dependency:
   - `globalKinshipServiceProvider` now injects `kinshipLoaderProvider`

4. **pubspec.yaml** — Removed `- assets/data/global/` from asset declarations

5. **6 JSON files deleted** from `assets/data/global/` (165 MB total):
   - arabic_kinship_production.json (43.9 MB)
   - korean_kinship_production.json (41.0 MB)
   - japanese_kinship_production.json (26.9 MB)
   - vietnamese_kinship_production_v2.json (19.5 MB)
   - russian_kinship_production_v2.json (19.6 MB)
   - chinese_kinship_production.json (14.5 MB)

### Server Changes

1. **kinship-data.controller.ts** — New controller serving kinship JSON:
   - `GET /api/v1/kinship/data/:languageCode` — streams JSON from disk
   - `GET /api/v1/kinship/data` — lists available languages
   - Language code whitelist prevents directory traversal
   - `@Public()` decorator (kinship data is not user-specific)
   - Cache-Control: public, max-age=86400 (24h CDN-friendly)
   - X-Content-Type-Options: nosniff
   - KINSHIP_DATA_DIR env var for configurable data directory

2. **kinship.module.ts** — Registered KinshipDataController

3. **kinship-assets/README.md** — Deployment instructions for production

## Key Results

- **APK size reduction**: ~165 MB removed from bundle
- **Estimated APK size**: ~93 MB (from ~258 MB) — now under Play Store 100 MB limit
- **TypeScript compilation**: 0 errors
- **No new packages required** (uses existing Dio, path_provider, flutter_riverpod)
