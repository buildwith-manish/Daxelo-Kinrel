# Daxelo Kinrel

**Indian Family Relationship Intelligence** — Map relationships in 14 Indian languages.

## Stack

| Layer | Technology |
|-------|-----------|
| Mobile/Desktop | Flutter (Android, iOS, Web, Windows, macOS, Linux) |
| Backend | NestJS |
| Database | PostgreSQL (via Supabase) + Drift (offline SQLite) |
| Auth | Supabase Auth |
| Storage | Supabase Storage |
| Realtime | Supabase Realtime + Socket.IO |
| ORM | Prisma (backend) + Drift (Flutter) |

## Structure

```
Daxelo-Kinrel/
├── Daxelo-Kinrel-App/   Flutter app (Android/iOS/Web/Desktop)
│   ├── lib/              Dart source code
│   ├── android/          Android native config
│   ├── ios/              iOS native config
│   ├── web/              Flutter Web config
│   ├── windows/          Windows native config
│   ├── macos/            macOS native config
│   ├── linux/            Linux native config
│   └── integration_test/ Integration tests
│
├── server/               NestJS backend (28 modules)
│   ├── src/              TypeScript source
│   │   ├── modules/      Feature modules (auth, families, graph, etc.)
│   │   ├── common/       Guards, interceptors, decorators, filters
│   │   └── prisma/       Prisma service
│   ├── prisma/           Prisma schema + Supabase migrations + RLS policies
│   ├── scripts/          Backup, restore, cron, pre-start validation
│   └── Dockerfile.production
│
├── deploy/               Deployment configs
│   ├── docker-compose.prod.yml
│   ├── nginx/            Nginx reverse proxy config
│   ├── systemd/          Systemd service file
│   └── scripts/          VPS setup, deploy, SSL, backup
│
├── store-assets/         Play Store listing assets
├── .github/workflows/    CI/CD (Flutter APK, Web, NestJS, Secret Scan)
└── .env.example          Environment variable reference
```

## Getting Started

### Flutter App

```bash
cd Daxelo-Kinrel-App
flutter pub get
flutter run
```

### NestJS Backend

```bash
cd server
npm install
npx prisma generate
npm run start:dev
```

### Docker (Production)

```bash
docker-compose -f deploy/docker-compose.prod.yml up -d
```

## Build APK

```bash
cd Daxelo-Kinrel-App
flutter build apk --release
```

## Build App Bundle

```bash
cd Daxelo-Kinrel-App
flutter build appbundle --release
```

## Features

- 🌳 Interactive family tree (500+ members, zoom/pan/collapse)
- 🏷️ @username system (Instagram-style, real-time availability)
- 🏠 Family ID system (KIN-AB12CD34, QR codes, deep links)
- 🤖 AI relationship discovery & explanations
- 🔍 Search (users, families, relationships — fuzzy + offline)
- 📴 Offline-first with Drift + background sync
- 🌐 14 Indian languages (Hindi, Tamil, Telugu, + 11 more)
- 🔔 Smart notifications (invites, birthdays, anniversaries)
- 🔒 Security (JWT, RLS, role guards, rate limiting)
- 📊 Family graph engine (8 core types → 50+ derived kinship terms)

## License

Proprietary — All rights reserved.
