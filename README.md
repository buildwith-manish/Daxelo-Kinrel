# DAXELO KINREL

**Indian Family Relationship Intelligence Platform**

A comprehensive platform for mapping, visualizing, and navigating Indian family relationships with support for 523 kinship terms across 13 Indian languages.

## 🏗️ Monorepo Structure

```
Daxelo-Kinrel/
├── Daxelo-Kinrel-App/       # Flutter Mobile & Web App
├── Daxelo-Kinrel-Server/    # Next.js API Server & Web Dashboard
├── Daxelo-Kinrel-Services/  # Micro-services & Database
└── Caddyfile                # Reverse proxy / gateway config
```

## 📱 Daxelo-Kinrel-App (Flutter)

Cross-platform Flutter app with Supabase auth, family tree visualization, kinship search, and path finder.

**Key Features:**
- 🔐 Supabase Authentication
- 👨‍👩‍👧‍👦 Interactive Family Tree
- 🔍 Kinship Path Finder
- 🇮🇳 523 Kinship Terms (13 Languages)
- 🎨 Kinrel Brand Design System

→ [See App README](./Daxelo-Kinrel-App/README.md)

## 🖥️ Daxelo-Kinrel-Server (Next.js)

Backend API server with 60+ endpoints for auth, families, kinship, graph traversal, communities, and more.

**Key Features:**
- 📡 60+ REST API endpoints
- 🔐 NextAuth.js authentication
- 🗄️ Prisma ORM (SQLite dev / PostgreSQL prod)
- 🌳 Graph traversal for family trees
- 📊 Dashboard & admin interfaces

→ [See Server README](./Daxelo-Kinrel-Server/README.md)

## ⚙️ Daxelo-Kinrel-Services (Micro-services)

Supporting micro-services and database management.

- 🌐 Flutter Web Server (SPA serving)
- 🗄️ SQLite Database (development)

→ [See Services README](./Daxelo-Kinrel-Services/README.md)

## 🚀 Quick Start

### Prerequisites
- Flutter SDK 3.8+
- Bun runtime (or Node.js 18+)
- Supabase project (for auth & database)

### 1. Server Setup
```bash
cd Daxelo-Kinrel-Server
cp .env.example .env    # Fill in your credentials
bun install
bun run db:push
bun run dev
```

### 2. App Setup
```bash
cd Daxelo-Kinrel-App
cp .env.example .env    # Fill in your Supabase credentials
flutter pub get
flutter run
```

### 3. Services Setup
```bash
cd Daxelo-Kinrel-Services/mini-services/flutter-web-server
bun install
bun run dev
```

## 🎨 Brand

| Token | Color | Usage |
|-------|-------|-------|
| Kinrel Orange | `#E8612A` | Primary |
| Amber | `#F59240` | Accent |
| Ember | `#C44A18` | Dark accent |
| Dark BG | `#13141E` | Background |
| Card BG | `#191B2C` | Cards |
| Elevated | `#202338` | Elevated surfaces |

**Fonts:** Outfit (display) · DM Sans (body) · DM Mono (mono)

## 📄 License

Proprietary — © Daxelo Kinrel
