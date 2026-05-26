# DAXELO KINREL — Services

Micro-services and utility scripts for the DAXELO KINREL platform.

## Services

### Flutter Web Server
Serves the Flutter web build with SPA fallback routing.

```bash
cd mini-services/flutter-web-server
bun install
bun run dev
```

Runs on port 3031 by default.

## Database

The `db/` directory contains the SQLite database file used in development.

> **Note**: The database file is excluded from git via `.gitignore`. Run `bun run db:push` from the Server directory to create the schema.

## Adding New Services

Each service should be in its own directory under `mini-services/`:

```
mini-services/
├── flutter-web-server/    # Flutter web static server
└── your-new-service/      # Add new services here
    ├── package.json       # or requirements.txt for Python
    ├── index.ts           # or main.py
    └── README.md
```

### Requirements for new services:
- Must be a new, independent project with its own `package.json` or `requirements.txt`
- Must define a specific port (not from env variable)
- Must support hot reload during development
