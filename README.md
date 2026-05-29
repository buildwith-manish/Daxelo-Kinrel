# Daxelo Kinrel
Indian Family Relationship Intelligence — map relationships in 14 Indian languages.

## Stack
Flutter 3.41.5 | NestJS | Supabase | PostgreSQL | Drift | Redis

## Structure
```
Daxelo-Kinrel/
├── Daxelo-Kinrel-App/  Flutter (Android/iOS/Web/Windows/Mac/Linux)
├── server/             NestJS backend (28 modules)
├── .github/workflows/  CI/CD (APK + Web + NestJS)
├── store-assets/       Play Store listing
├── docker-compose.yml
└── README.md
```

## Run Flutter
```bash
cd Daxelo-Kinrel-App && flutter pub get && flutter run
```

## Run Server
```bash
cd server && npm install && npm run start:dev
```

## Docker
```bash
docker-compose up
```

## Build APK
```bash
cd Daxelo-Kinrel-App && flutter build apk --release
```

## Build AAB
```bash
cd Daxelo-Kinrel-App && flutter build appbundle --release
```
