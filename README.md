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

## CI/CD Status

| Workflow | Trigger | Status |
|----------|---------|--------|
| Flutter CI | Push/PR to main (`Daxelo-Kinrel-App/**`) | Analyze + Test |
| Backend CI | Push/PR to main (`server/**`) | Build + Test |
| Build Flutter APK | Push to main, manual | Build APK artifact |
| NestJS CI | Push/PR to main | Build + Test |
| Release Build | Tag `v*` | APK + GitHub Release |
| Secret Leak Scan | Push, PR, daily | Gitleaks scan |
| Deploy to VPS | Push to main (`server/**`) | SSH deploy |

## Structure

```
Daxelo-Kinrel/
├── Daxelo-Kinrel-App/   Flutter app (Android/iOS/Web/Desktop)
│   ├── lib/              Dart source code
│   │   ├── core/         Database, services, networking, theme
│   │   ├── features/     Feature modules (auth, family, kinship, etc.)
│   │   ├── data/         Data repositories
│   │   ├── presentation/ Shared screens & providers
│   │   └── shared/       Shared widgets & painters
│   ├── android/          Android native config
│   ├── test/             Unit & widget tests
│   └── integration_test/ Integration tests
│
├── server/               NestJS backend (28 modules)
│   ├── src/              TypeScript source
│   │   ├── modules/      Feature modules (auth, families, graph, etc.)
│   │   ├── common/       Guards, interceptors, decorators, filters
│   │   └── prisma/       Prisma service
│   ├── prisma/           Prisma schema
│   ├── scripts/          Backup, restore, cron, pre-start validation
│   ├── Dockerfile
│   ├── Dockerfile.koyeb
│   └── Dockerfile.production
│
├── deploy/               Deployment configs
│   ├── docker-compose.prod.yml
│   ├── nginx/            Nginx reverse proxy config
│   ├── systemd/          Systemd service file
│   └── scripts/          VPS setup, deploy, SSL, backup
│
├── store-assets/         Play Store listing assets
├── .github/workflows/    CI/CD (7 workflows)
└── .env.example          Environment variable reference
```

## Getting Started

### Flutter App

```bash
cd Daxelo-Kinrel-App
flutter pub get
dart run build_runner build   # Generate Drift code
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
flutter pub get
dart run build_runner build
flutter build apk
```

## Build App Bundle

```bash
cd Daxelo-Kinrel-App
flutter build appbundle --release
```

## Testing

### Flutter

```bash
cd Daxelo-Kinrel-App
flutter test                    # Unit tests
flutter test integration_test/  # Integration tests (requires device)
```

### NestJS

```bash
cd server
npm test              # Run 102 unit tests
npm run test:watch    # Watch mode
npm run test:cov      # With coverage
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

## Deployment

### Koyeb (Backend)

See `server/.koyeb/config.yaml` for configuration.
Set secrets via Koyeb dashboard → Service → Environment Variables.

### VPS (Full Stack)

See `deploy/DEPLOYMENT.md` and `deploy/COOLIFY.md` for VPS setup.

### Required Secrets

Configure these in GitHub Secrets for CI/CD:
- `KEYSTORE_BASE64` — Base64-encoded Android keystore (for signed release APK)
- `KEYSTORE_PASSWORD` — Keystore password
- `KEY_PASSWORD` — Key alias password
- `VPS_HOST` — Oracle Cloud VPS IP
- `VPS_USER` — SSH user
- `VPS_SSH_KEY` — SSH private key

## License

Proprietary — All rights reserved.
