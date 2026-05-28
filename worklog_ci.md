---
Task ID: 1
Agent: Main Agent
Task: Create separate GitHub Actions workflows for Flutter APK build, NestJS backend CI, and gitleaks secret scan; fix all build errors

Work Log:
- Explored project structure: git root at /home/z/my-project/ with Flutter app in Daxelo-Kinrel-App/ and NestJS backends in Daxelo-Kinrel-Server/ and backend/
- Deleted old ci.yml workflow (single combined workflow with issues)
- Created 3 new workflows: build_apk.yml, nestjs.yml, gitleaks.yml
- Fixed "git exit code" error by adding fetch-depth: 0 to all checkout steps
- Fixed "Node.js 20 deprecated" by using all v4 actions (actions/checkout@v4, actions/setup-java@v4, actions/setup-node@v4, actions/upload-artifact@v4)
- Fixed APK artifact upload with correct path: Daxelo-Kinrel-App/build/app/outputs/flutter-apk/app-release.apk
- Updated android/app/build.gradle.kts with Kotlin DSL signing config (reads key.properties, falls back to debug)
- Added .gitignore entries for *.jks, *.keystore, Daxelo-Kinrel-App/android/key.properties
- Created tsconfig.build.json for Daxelo-Kinrel-Server to scope NestJS compilation (exclude Next.js app/ files)
- Updated nest-cli.json to explicitly use tsconfig.build.json
- Fixed 27 NestJS TypeScript errors: type→relationshipKey, Person.relationship→relationshipsFrom/relationshipsTo, fixed Prisma include queries
- Verified Flutter analyze passes with 0 issues
- Verified NestJS tsc --noEmit passes with 0 errors
- Verified NestJS npm run build produces dist/main.js
- Committed as 27b56db and pushed to origin/main

Stage Summary:
- 3 separate workflows created replacing the old ci.yml
- All CI errors fixed: git exit code, Node.js 20 deprecation, APK artifact path
- 27 NestJS TypeScript compilation errors fixed (Prisma schema mismatch)
- Android signing config properly configured with fallback to debug
- Push: 27b56db to main
