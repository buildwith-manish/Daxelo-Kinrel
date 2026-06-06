---
Task ID: Phase 0
Agent: Main Agent
Task: Phase 0 — Emergency Fixes (BUG-02,03,04,05,06,07→0.9,12,13,14,17,21)

Work Log:
- 0.1: Expanded root .env.example from 1 variable to 25+ variables with all sections
- 0.2: Gated Swagger behind NODE_ENV !== 'production' in server/src/main.ts
- 0.3: Fixed iOS CORS typo: 'capabile://' → 'kinrel://', 'com.daxelo.kinrel' → 'com.daxelo.kinrel://'
- 0.3b: Fixed CORS localhost bypass to only work in development (NODE_ENV === 'development')
- 0.4: Added TOTP replay protection in auth.service.ts verify2FA() and loginVerify2FA() — Redis setex before verify, mark used after; window reduced from 2 → 1
- 0.5: Upgraded multer from ^1.4.5-lts.1 → ^2.1.1; @types/multer updated to ^2.1.0
- 0.6: Restored image_cropper: ^5.0.0 in pubspec.yaml
- 0.7: Downloaded and added Bold/Medium/SemiBold weights for NotoSansDevanagari, NotoSansTamil, NotoSansTelugu, NotoSansBengali (12 font files)
- 0.8: Standardized Flutter version in build-apk-release.yml from 3.44.0 → 3.44.1
- 0.9: Removed AuthTokens Drift table from app_database.dart — schema v4 with migration to DROP TABLE; tokens already in SecureStorageService
- 0.10: Added Redis injection + invalidateGraphCache() to RelationshipsService — called on create() and remove()
- 0.11: Increased graph CACHE_TTL from 60s → 300s in graph.service.ts

Stage Summary:
- 10 files modified, 12 font files added
- TypeScript compilation: 0 errors
- Backend tests: 107/107 passing
- Flutter/Dart CLI unavailable in sandbox — build_runner must be run locally
- All Phase 0 items complete
