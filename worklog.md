# Worklog

---
Task ID: 1
Agent: Main Orchestrator
Task: Production CI/CD Pipeline — All 9 Phases

Work Log:
- Phase 1: Comprehensive repository audit (Flutter + NestJS + GitHub Actions)
- Phase 2: Fixed 3 Flutter errors (ProfileModel uninitialized fields, Value<DateTime> type mismatch)
- Phase 3: Fixed NestJS backend (added test scripts, fixed DTO decorators, removed 7 legacy modules, fixed Dockerfile.production, standardized ports, registered GraphEngineService, removed dead code, fixed jest/ts-jest version mismatch)
- Phase 4: Created 4 new GitHub Actions workflows (flutter-ci, backend-ci, flutter-apk, release), improved 3 existing (nestjs, gitleaks, deploy-vps)
- Phase 5: Monitored GitHub Actions, fixed APK signing failure, pushed 3 fix commits until all green
- Phase 6: APK artifact verified (49-51 MB, uploaded to GitHub)
- Phase 7: Standardized all deployment ports to 3000 across Dockerfiles, docker-compose, nginx, Koyeb, Coolify configs
- Phase 8: Removed 14 dead Flutter files, 5 dead NestJS files, unused packages (zod, @nestjs/serve-static, passport-google-oauth20, riverpod_annotation)
- Phase 9: Final verification — Flutter 0 errors/0 warnings, NestJS 102 tests pass, all GitHub Actions green

Stage Summary:
- Flutter: 0 errors, 0 warnings, 88 info-level hints, 1 test passing
- NestJS: 3 test suites, 102 tests all passing, build succeeds
- GitHub Actions: NestJS CI ✅, Backend CI ✅, Flutter CI ✅, Build Flutter APK ✅, Secret Leak Scan ✅
- APK artifact: 49-51 MB, available for download
- Deploy to VPS: Requires VPS secrets configuration (expected failure)
- 118 files changed in initial commit, 3 follow-up fix commits
- Total: 6,908 lines deleted (dead code), 1,298 lines added (fixes/workflows)

---
Task ID: 2
Agent: Main Orchestrator
Task: Fix Google Sign-In ApiException:10 and Render build failure

Work Log:
- Analyzed user screenshot showing PlatformException(sign_in_failed, ApiException: 10)
- Identified root cause: GoogleSignIn on Android had no clientId/serverClientId, google-services.json missing Android OAuth client
- Fixed _buildGoogleSignIn() to pass clientId (Android) + serverClientId (web) for ID token generation
- Updated google-services.json with Android OAuth client (type 1) entry with SHA-1 certificate hash
- Pushed fix, GitHub Actions Flutter APK build passed ✅
- Then diagnosed Render build failure: three compounding issues found:
  1. npm ci peer dependency conflict (@nestjs/schedule v4 vs @nestjs/common v11)
  2. NPM_CONFIG_PRODUCTION=true in nixpacks.toml skipping devDependencies needed for build
  3. Unused sharp dependency requiring vips-dev on Alpine
- Created server/.npmrc with legacy-peer-deps=true
- Upgraded @nestjs/schedule from ^4.0.0 to ^6.0.0
- Removed unused sharp dependency
- Regenerated package-lock.json
- Fixed nixpacks.toml (removed NPM_CONFIG_PRODUCTION, removed --ignore-scripts)
- Fixed Dockerfile and Dockerfile.production (added vips-dev, .npmrc copy, npm ci without --ignore-scripts)
- Created render.yaml blueprint at repo root for proper Render configuration
- All GitHub Actions passing: NestJS CI ✅, Backend CI ✅, Flutter APK ✅, Secret Leak Scan ✅

Stage Summary:
- Google Sign-In fix: clientId + serverClientId now passed on Android/iOS
- Render build fix: 6 server files changed (package.json, package-lock.json, .npmrc, nixpacks.toml, Dockerfile, Dockerfile.production)
- render.yaml created for Render deployment configuration
- Commits: 028f23c (Google Sign-In fix), c99c7fe (Render build fix), ed16002 (render.yaml)
- User needs to: (1) add debug SHA-1 to Google Cloud Console, (2) configure Render environment variables, (3) set Render rootDir to server

---
Task ID: 3
Agent: Main Orchestrator
Task: Fix Render deployment — switch Prisma from SQLite to PostgreSQL + fix Node version

Work Log:
- Diagnosed server returning 404 on Render (x-render-routing: no-server — container never started)
- Found ROOT CAUSE #1: Prisma schema had `provider = "sqlite"` but production database is Supabase PostgreSQL
- Changed prisma/schema.prisma: `provider = "postgresql"`, added `directUrl` env var for PgBouncer
- Fixed SupportTicket relation constraint name collision (PostgreSQL requires unique FK names)
- Added `@relation("SupportTicketUser")` to User.supportTickets to match SupportTicket.user
- Removed vips-dev from Dockerfiles (sharp was already removed — no need for vips)
- Fixed Dockerfile healthcheck to use $PORT env var (Render uses 10000, not 3000)
- Fixed nixpacks.toml (removed stale vips-dev reference)
- Updated render.yaml with DIRECT_URL env var

- Found ROOT CAUSE #2: NestJS 11 requires Node >= 20, but Render defaults to Node 18
  - @nestjs/cli@11: engines.node >= 20.11
  - @nestjs/core@11: engines.node >= 20
  - Node 18.20.0 causes npm ci to fail with exit status 1 (silent — postinstall scripts fail)
- Added server/.node-version with "20"
- Added server/.nvmrc with "20"
- Added NODE_VERSION=20 to render.yaml env vars
- Regenerated package-lock.json for clean npm ci
- Removed empty root package-lock.json
- Verified full build pipeline: npm ci → prisma generate → nest build — all pass locally

Stage Summary:
- Commit c462685: Prisma sqlite → postgresql + Dockerfile/nixpacks fixes
- Commit c76d411: Node 20 requirement + .node-version + regenerated lockfile
- Server still returning 404 because existing Render service needs Dashboard changes:
  1. Add NODE_VERSION=20 to Render Environment variables
  2. Set rootDir to server (or delete/recreate from render.yaml blueprint)
  3. Ensure Docker Command is empty or "node dist/main"
  4. Ensure all required env vars are set (DATABASE_URL, DIRECT_URL, JWT_ACCESS_SECRET, etc.)
