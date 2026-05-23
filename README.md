# DAXELO KINREL
### Indian Family Relationship Intelligence Platform

## Architecture

| Part | Technology | Purpose |
|------|-----------|---------|
| Mobile App | Flutter 3.x / Dart | Android + iOS |
| API Server | NestJS 11.x | REST API + WebSocket |
| Database | PostgreSQL + Prisma | Data persistence |
| Auth | JWT + Google OAuth | Authentication |
| Realtime | Socket.io | Live graph updates |

## Repository Structure

```
Daxelo-Kinrel-App/      Flutter mobile application
Daxelo-Kinrel-Server/   NestJS API server
```

## Quick Start

### API Server
```bash
cd Daxelo-Kinrel-Server
cp .env.example .env
# Fill in DATABASE_URL, JWT secrets, etc.
npm install
npm run db:generate
npm run db:push
npm run start:dev
```

### Flutter App
```bash
cd Daxelo-Kinrel-App
cp .env.example .env
flutter pub get
flutter run
```

## API Endpoints

Base URL: `http://localhost:3001/api`

```
Auth:         POST /api/auth/register
              POST /api/auth/login
              POST /api/auth/refresh
              GET  /api/auth/google

Family:       GET  /api/v1/families
              POST /api/v1/families
              GET  /api/v1/families/:id

Kinship:      GET  /api/v1/kinship
              GET  /api/v1/kinship?key=fathers_brother
              GET  /api/v1/kinship?q=chacha
              GET  /api/v1/kinship?category=in_laws

Graph:        GET  /api/v1/graph/:familyId
              GET  /api/v1/graph/:familyId/tree
              GET  /api/v1/graph/:familyId/path

Health:       GET  /api/health
```

## Kinship Database

| Language | Relationships | Dialects | Version |
|----------|--------------|---------|---------|
| Indian   | 5,359        | 15 langs | v4.1.0 |
| Chinese  | 5,358        | 7 dialects | v3.2.1 |
| Japanese | 4,509        | 6 dialects | v1.0.1 |
| Korean   | 4,913        | 6 dialects | v1.0.0 |

**Indian Kinship v4.1.0 Languages:** Hindi, Bengali, Telugu, Marathi, Tamil,
Urdu, Gujarati, Kannada, Malayalam, Odia, Punjabi, Assamese, Sanskrit,
Sindhi, English

## Environment Variables

See `Daxelo-Kinrel-Server/.env.example` for all required environment variables.

## License
Proprietary — All rights reserved.
