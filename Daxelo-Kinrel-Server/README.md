# DAXELO KINREL — Next.js Server

Backend API server for the DAXELO KINREL family relationship intelligence platform.

## Tech Stack

- **Framework**: Next.js 16 (App Router)
- **Language**: TypeScript 5
- **Database**: Prisma ORM (SQLite dev / PostgreSQL prod)
- **Auth**: NextAuth.js v4
- **UI**: React 19, Tailwind CSS 4, shadcn/ui
- **Runtime**: Bun (preferred), Node.js fallback

## Getting Started

### Prerequisites

- Bun runtime (or Node.js 18+)
- SQLite (dev) or PostgreSQL (prod)

### Setup

1. Copy `.env.example` to `.env` and fill in your credentials:
   ```bash
   cp .env.example .env
   ```

2. Install dependencies:
   ```bash
   bun install
   ```

3. Push database schema:
   ```bash
   bun run db:push
   ```

4. Run the development server:
   ```bash
   bun run dev
   ```

### Build for Production

```bash
   bun run build
   bun run start
```

## API Routes

### Auth
- `POST /api/auth/register` — User registration
- `GET/POST /api/auth/[...nextauth]` — NextAuth handlers

### Families
- `GET/POST /api/families` — List/Create families
- `GET/PATCH/DELETE /api/families/:id` — Family CRUD
- `GET/POST /api/families/:id/persons` — Person management
- `GET/POST /api/families/:id/relationships` — Relationship management

### Kinship (v1)
- `GET /api/v1/kinship` — Search kinship terms
- `GET /api/v1/kinship/:term` — Get kinship term details

### Graph
- `GET /api/v1/graph/tree` — Family tree data
- `GET /api/v1/graph/path` — Path between two persons

### And 40+ more API routes for communities, posts, notifications, etc.

## Project Structure

```
src/
├── app/              # Next.js App Router pages & API routes
│   ├── api/          # 60+ API route handlers
│   ├── (auth)/       # Auth pages (sign-in, sign-up)
│   └── (dashboard)/  # Dashboard pages
├── components/       # React components (brand, kinrel, ui)
├── hooks/            # Custom React hooks
├── lib/              # Business logic & utilities
│   ├── data/         # indian-kinship.json (523 relationships)
│   └── ...           # Various service modules
├── styles/           # Brand token CSS
└── types/            # TypeScript type definitions
```
