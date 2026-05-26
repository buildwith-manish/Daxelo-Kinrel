# DAXELO KINREL — NestJS Backend

NestJS backend for the DAXELO KINREL Indian family relationship intelligence platform.

## Quick Start

```bash
# Install dependencies
bun install

# Generate Prisma client
bun run db:generate

# Start development server
bun run start:dev
```

Server runs on http://localhost:3001/api

## Environment

Copy `.env.example` to `.env` and fill in values.

## Running alongside Next.js

- Next.js (frontend + API): port 3000
- NestJS (backend): port 3001

During transition, both can run simultaneously. Point your Flutter app to port 3001 for the new backend.
