# Task: Create Coolify Deployment Files

## Summary
Created 4 deployment files for the Daxelo-Kinrel project to support Coolify (self-hosted PaaS) deployment on Oracle Cloud VPS, replacing the manual Docker approach.

## Files Created

### 1. `deploy/COOLIFY.md` (1,124 lines)
Comprehensive step-by-step guide covering:
- Why Coolify vs manual Docker (comparison table)
- Architecture overview with ASCII diagram showing Coolify's Traefik replacing Nginx
- 8 detailed deployment steps (VPS setup → Coolify install → deploy)
- Post-deploy Flutter app update instructions
- Complete environment variables reference (15 minimum + 30+ optional)
- Ongoing operations (update, logs, migrations, rollback)
- 12 troubleshooting scenarios with fixes
- Migration guide from manual Docker to Coolify
- Cost breakdown ($0/month)
- Quick start summary (30 minutes total)

### 2. `deploy/coolify-env-template.md` (223 lines)
Quick reference of all env vars organized by 13 sections:
- Each variable has: value format, secret status, where to find it
- Step-by-step instructions for finding Supabase, Firebase, Cloudinary, etc. keys
- Quick setup checklist (15 minimum vars for first deploy)
- Coolify UI tips for bulk import, secret masking, variable references

### 3. `server/nixpacks.toml` (59 lines)
Nixpacks build configuration for Coolify:
- Provider: node
- Install phase: `npm ci --ignore-scripts` + `npx prisma generate`
- Build phase: `npm run build`
- Start phase: `node dist/main`
- Variables: NODE_ENV=production, NPM_CONFIG_PRODUCTION=true

### 4. `server/coolify.json` (64 lines)
Coolify deployment reference document:
- Documents intended topology (API + Redis + optional PostgreSQL)
- Service definitions with ports, health checks, resource limits
- Domain configuration (api.kinrel.app with Let's Encrypt)
- Notes explaining this is a planning document (Coolify UI is primary)

## Key Decisions
- **Nixpacks over Docker** as primary build pack (uses nixpacks.toml) — simpler, but Dockerfile still works as alternative
- **Supabase PostgreSQL** over Coolify's built-in PostgreSQL — free managed DB with backups
- **Let's Encrypt** over Cloudflare Origin certs — auto-provisioned and auto-renewed by Traefik
- **Full SSL mode** in Cloudflare (not Full Strict) — simpler with Let's Encrypt certs
- **Minimum 15 env vars** for first deploy — all other sections are optional/incremental
