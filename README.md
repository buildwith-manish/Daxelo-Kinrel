# Daxelo Kinrel
Indian Family Relationship Intelligence App
Map family relationships in 14 Indian languages.

## Stack
- Flutter 3.41.5 — Android, iOS, Windows, Mac, Linux, Web
- NestJS — Backend API (28 modules)
- Supabase — Auth, Storage, Realtime
- PostgreSQL via Supabase — Database
- Drift (SQLite) — Offline local cache
- Redis — Caching and queues

## Structure
```
Daxelo-Kinrel/
├── Daxelo-Kinrel-App/    ← Flutter app
│   ├── android/
│   ├── ios/
│   ├── web/
│   ├── windows/
│   ├── macos/
│   ├── linux/
│   └── lib/
│       ├── core/
│       ├── features/
│       ├── shared/
│       └── main.dart
├── server/               ← NestJS backend
│   ├── src/
│   │   ├── modules/      ← 28 feature modules
│   │   └── main.ts
│   ├── prisma/
│   ├── Dockerfile
│   └── package.json
├── .github/workflows/    ← CI/CD
└── docker-compose.yml
```

## Run Flutter App
```bash
cd Daxelo-Kinrel-App
flutter pub get
dart run build_runner build
flutter run
```

## Run NestJS Server
```bash
cd server
cp .env.example .env
# Fill in .env values
npm install
npm run start:dev
```

## Run with Docker
```bash
cp server/.env.example server/.env
# Fill in server/.env
docker-compose up
```

## Build APK
```bash
cd Daxelo-Kinrel-App
flutter build apk --release
# APK at: build/app/outputs/flutter-apk/app-release.apk
```

## Security
- Row Level Security (RLS) enabled on all Supabase tables
- Users can only access their own family data
- JWT tokens rotated every 15 minutes
- All secrets in environment variables, never in code
