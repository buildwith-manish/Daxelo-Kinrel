# Daxelo-Kinrel — Koyeb Deployment Guide

> **Deploy the Daxelo-Kinrel NestJS API to production in under 15 minutes using Koyeb — a fully managed serverless platform with a generous free tier and zero infrastructure management.**

---

## Table of Contents

1. [What is Koyeb?](#what-is-koyeb)
2. [Prerequisites](#prerequisites)
3. [Step 1: Create Koyeb Account](#step-1-create-koyeb-account)
4. [Step 2: Create Service](#step-2-create-service)
5. [Step 3: Configure Custom Domain](#step-3-configure-custom-domain)
6. [Step 4: Configure Cloudflare](#step-4-configure-cloudflare)
7. [Step 5: Verify Deployment](#step-5-verify-deployment)
8. [Step 6: Auto-Deploy](#step-6-auto-deploy)
9. [Step 7: Run Prisma Migrations](#step-7-run-prisma-migrations)
10. [Monitoring](#monitoring)
11. [Troubleshooting](#troubleshooting)
12. [Cost](#cost)

---

## What is Koyeb?

**Koyeb** is a fully managed serverless platform that runs your applications globally with zero infrastructure management. Think of it as a modern Heroku with built-in global edge routing, auto-scaling, and native Docker support.

### Why Koyeb for Daxelo-Kinrel?

| Feature | Benefit |
|---------|---------|
| **Free tier** | 1 nano service (512 MB RAM, 0.1 vCPU) — enough for initial launch |
| **Docker support** | Uses our `Dockerfile.koyeb` directly — no build pack guessing |
| **Auto-deploy** | Push to GitHub → Koyeb rebuilds and deploys automatically |
| **Global edge** | Automatic SSL, HTTP/2, and global routing |
| **Zero ops** | No VPS to manage, no Docker to install, no Nginx to configure |
| **Built-in health checks** | Monitors `/api/health` and auto-restarts on failure |

### Koyeb Free Tier Limits

| Resource | Limit |
|----------|-------|
| Services | 1 nano service |
| RAM | 512 MB |
| CPU | 0.1 vCPU |
| Disk | 2 GB |
| Bandwidth | 100 GB/month |
| Custom domains | Unlimited |
| SSL | Auto (Let's Encrypt) |

> The nano instance is sufficient for ~50–100 concurrent users with the Daxelo-Kinrel NestJS API. When you outgrow it, upgrade to a micro instance ($5/month for 1 GB RAM, 0.5 vCPU).

---

## Prerequisites

| Requirement | Status | Notes |
|-------------|--------|-------|
| Koyeb account | Required | Free signup at koyeb.com |
| GitHub repo | Required | `buildwith-manish/Daxelo-Kinrel` |
| Supabase project | Required | Free tier at supabase.com |
| Cloudflare account | Required | Free plan, for DNS management |
| Domain name | Required | `kinrel.app` (or your domain) |

---

## Step 1: Create Koyeb Account

1. Go to [koyeb.com](https://koyeb.com) and click **Sign Up**
2. Sign up using your **GitHub account** (recommended — simplifies repo access) or email
3. Verify your email address if you signed up with email
4. You'll land on the Koyeb dashboard

> The free tier activates automatically — no credit card required.

---

## Step 2: Create Service

### 2.1 Start Creating a Service

1. In the Koyeb dashboard, click **Create Service**
2. Select **Deploy from GitHub**

### 2.2 Connect Your GitHub Repository

1. Click **Connect GitHub** if this is your first time
2. Authorize Koyeb to access your GitHub account
3. Select the repository: **`buildwith-manish/Daxelo-Kinrel`**
4. Select the branch: **`main`**

### 2.3 Configure Build Settings

| Setting | Value | Notes |
|---------|-------|-------|
| **Build directory** | `server` | CRITICAL — tells Koyeb to build from the `server/` subdirectory |
| **Dockerfile path** | `Dockerfile.koyeb` | Our production-optimized multi-stage Dockerfile |
| **Port** | `3001` | The port NestJS listens on |

> **Why `server` as build directory?** The repository is a monorepo containing both the Flutter app (`Daxelo-Kinrel-App/`) and the NestJS backend (`server/`). Setting the build directory to `server` ensures Koyeb only builds the backend, not the entire monorepo.

### 2.4 Configure Environment Variables

Click **Add Environment Variable** and add the following. See **[`deploy/koyeb-env-setup.md`](./koyeb-env-setup.md)** for the complete reference with instructions on where to find each value.

#### Minimum Required (First Deploy)

| Variable | Value | Secret? |
|----------|-------|---------|
| `NODE_ENV` | `production` | No |
| `PORT` | `3001` | No |
| `API_PREFIX` | `api` | No |
| `FRONTEND_URL` | `https://kinrel.app` | No |
| `DATABASE_URL` | `postgresql://postgres.REF:PASS@aws-0-REGION.pooler.supabase.com:6543/postgres` | Yes |
| `DIRECT_URL` | `postgresql://postgres:PASS@db.REF.supabase.co:5432/postgres` | Yes |
| `JWT_ACCESS_SECRET` | *(64-char hex)* | Yes |
| `JWT_ACCESS_EXPIRATION` | `15m` | No |
| `JWT_REFRESH_SECRET` | *(64-char hex)* | Yes |
| `JWT_REFRESH_EXPIRATION` | `7d` | No |
| `SUPABASE_URL` | `https://promxswvsnvilplmrtsj.supabase.co` | No |
| `SUPABASE_ANON_KEY` | `eyJhb...` | No |
| `SUPABASE_JWT_SECRET` | *(long string)* | Yes |
| `SUPABASE_SERVICE_ROLE_KEY` | `eyJhb...` | Yes |
| `CORS_ORIGINS` | `https://kinrel.app,https://www.kinrel.app,capabile://,com.daxelo.kinrel` | No |

> **Tip:** Generate JWT secrets on your local machine with `openssl rand -hex 32` (run twice — once for access, once for refresh).

> **No Redis on Koyeb free tier:** The free tier only supports 1 service. Set `REDIS_URL` to empty or omit it — the app gracefully degrades without Redis (uses in-memory caching instead). See the [Redis note](#redis-consideration) below.

### 2.5 Select Instance Type

| Setting | Value |
|---------|-------|
| **Instance type** | **Nano** (free) |
| **Region** | **Frankfurt (fra)** — closest to India with good latency on the free tier |

> **Region choice:** Koyeb's free tier is available in Frankfurt (fra), Washington DC (iad), and Singapore (sin). Frankfurt provides the best balance of latency to India and Europe. If your primary audience is Southeast Asia, choose Singapore.

### 2.6 Deploy

1. Click **Deploy**
2. Koyeb will:
   - Pull the repository from GitHub
   - Build the Docker image using `Dockerfile.koyeb`
   - Run the container on a nano instance
   - Provision automatic SSL
   - Assign a Koyeb subdomain (e.g., `kinrel-api-abc123.koyeb.app`)

**Build time:** ~3–5 minutes (first build). Subsequent builds are faster due to Docker layer caching.

---

## Step 3: Configure Custom Domain

### 3.1 Add Your Domain in Koyeb

1. Go to your service → **Domains** tab
2. Click **Add Domain**
3. Select **Custom Domain**
4. Enter: `api.kinrel.app`
5. Koyeb will display the DNS target — it looks like:
   ```
   kinrel-api-abc123.koyeb.app
   ```
6. Copy the CNAME target

### 3.2 Koyeb Auto-SSL

Koyeb automatically provisions and renews Let's Encrypt SSL certificates for custom domains. No manual certificate management required.

> **Important:** The DNS record must be properly configured (Step 4) before Koyeb can provision the SSL certificate. There may be a 1–2 minute delay after DNS propagation before the certificate is issued.

---

## Step 4: Configure Cloudflare

### 4.1 Add DNS Record

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com/)
2. Select the `kinrel.app` domain
3. Go to **DNS → Records**
4. Add a record:

| Type | Name | Target | Proxy | TTL |
|------|------|--------|-------|-----|
| CNAME | `api` | `kinrel-api-abc123.koyeb.app` | ☁️ Proxied | Auto |

> **Alternative:** If Koyeb provides an IP address instead of a CNAME target, use an **A** record instead.

> **Cloudflare Proxy (orange cloud):** Recommended — gives you DDoS protection, WAF, and CDN caching for free. If you experience issues with WebSocket connections, temporarily switch to DNS Only (grey cloud) for testing.

### 4.2 Configure SSL/TLS

1. Go to **SSL/TLS → Overview**
2. Set mode to **Full** (not Full Strict)

> **Why Full?** Koyeb already provides a valid Let's Encrypt certificate on its end. **Full** mode means Cloudflare validates the connection to the origin but doesn't need strict CA verification, which is simpler. **Full (Strict)** also works since Koyeb's certificates are publicly trusted.

### 4.3 Additional Cloudflare Settings

| Setting | Location | Value | Reason |
|---------|----------|-------|--------|
| Always Use HTTPS | SSL/TLS → Edge Certificates | ON | Redirect HTTP to HTTPS |
| Minimum TLS Version | SSL/TLS → Edge Certificates | TLS 1.2 | Security baseline |
| WebSocket | Network → WebSockets | ON | Required for Socket.IO |
| Rocket Loader | Speed → Optimization | OFF | Can break WebSocket connections |
| Brotli | Speed → Optimization | ON | Compress API responses |

### 4.4 Configure WebSocket Support

Cloudflare supports WebSocket by default on all plans. For the Socket.IO path (`/socket.io/`):

1. Ensure **WebSocket** is enabled (default ON)
2. Ensure **Rocket Loader** is OFF
3. SSL mode must be **Full** or **Full (Strict)**

> **Cloudflare Free plan WebSocket timeout:** 100 seconds. If your Socket.IO connections idle longer than this, implement ping/pong heartbeat (Socket.IO does this by default with `pingInterval: 25000`).

---

## Step 5: Verify Deployment

### 5.1 Check Service Status

1. Go to the Koyeb dashboard → your service
2. Verify the status shows **Running** (green indicator)
3. Click **Logs** to see the startup output

You should see:
```
🚀 DAXELO KINREL Server running on http://localhost:3001/api
📡 API routes: /api/* and /api/v1/* for Flutter compatibility
```

### 5.2 Health Check

```bash
# Using the Koyeb subdomain
curl https://kinrel-api-abc123.koyeb.app/api/health

# Expected response:
# {"status":"ok","db":"connected","uptime":42,"memory":45.23,"ts":1700000000000}

# After custom domain DNS propagates
curl https://api.kinrel.app/api/health
```

### 5.3 API Test

```bash
# Test a public endpoint
curl https://api.kinrel.app/api/health

# Test WebSocket (Socket.IO)
npm install -g wscat
wscat -c wss://api.kinrel.app/socket.io/?EIO=4&transport=websocket
```

### 5.4 Check Health Status in Koyeb

Koyeb's dashboard shows the health check status:
- **Healthy** (green): Service is responding to `/api/health`
- **Unhealthy** (red): Health check is failing — check logs
- **Starting** (yellow): Service is still booting up

---

## Step 6: Auto-Deploy

### 6.1 Enable Auto-Deploy

Koyeb auto-deploys by default when you push to the connected branch. To verify or configure:

1. Go to your service → **Settings** → **Build & Deploy**
2. Ensure **Auto-deploy** is enabled for the `main` branch

### 6.2 How It Works

```
git push origin main
    │
    │  GitHub webhook fires
    ▼
Koyeb detects the push
    │
    │  Triggers a new build
    ▼
Build Docker image from Dockerfile.koyeb
    │
    │  Build completes (~2-3 min)
    ▼
Deploy new container (replaces old one)
    │
    │  Health check passes
    ▼
Service is live with new code ✅
```

### 6.3 Zero-Downtime Deploys

Koyeb performs rolling deployments — the new container starts and passes health checks before the old container is terminated. This ensures zero downtime during deployments.

### 6.4 Manual Redeploy

If you need to redeploy without a code change (e.g., after updating environment variables):

1. Go to your service → **Deployments** tab
2. Click **Redeploy** on the latest deployment

---

## Step 7: Run Prisma Migrations

When you change the Prisma schema, you need to apply migrations to the database. Since Koyeb doesn't provide persistent SSH access like a VPS, use one of these methods:

### Option A: Run Migrations Locally (Recommended)

```bash
# On your local machine, with the server/ directory
cd server/

# Set the production DATABASE_URL (direct connection, port 5432)
export DATABASE_URL="postgresql://postgres:PASS@db.REF.supabase.co:5432/postgres"
export DIRECT_URL="postgresql://postgres:PASS@db.REF.supabase.co:5432/postgres"

# Run migrations
npx prisma migrate deploy
```

> **IMPORTANT:** Use the **direct** connection string (port 5432) for migrations, not the pooled connection (port 6543). Prisma migrations require a direct connection.

### Option B: Run via Koyeb Console

1. Go to your service → **Console** tab
2. This opens a web terminal inside the running container
3. Run:

```bash
# Set the direct URL for migration
export DIRECT_URL="postgresql://postgres:PASS@db.REF.supabase.co:5432/postgres"

# Run migrations
npx prisma migrate deploy
```

> **Note:** The Koyeb console is ephemeral — any changes made inside the container are lost on redeploy. Migrations apply to the external Supabase database, so they persist.

### Option C: Run via Koyeb CLI

```bash
# Install Koyeb CLI
npm install -g @koyeb/cli

# Login
koyeb login

# Open a shell in the service
koyeb service exec kinrel-api -- sh

# Inside the shell
npx prisma migrate deploy
```

### Option D: Add a Migration Script (CI/CD)

Create a GitHub Actions workflow that runs migrations before Koyeb deploys:

```yaml
# .github/workflows/migrate.yml
name: Run Migrations
on:
  push:
    branches: [main]
    paths:
      - 'server/prisma/**'

jobs:
  migrate:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: server
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
      - run: npm ci
      - run: npx prisma generate
      - run: npx prisma migrate deploy
        env:
          DATABASE_URL: ${{ secrets.DIRECT_URL }}
          DIRECT_URL: ${{ secrets.DIRECT_URL }}
```

---

## Monitoring

### Koyeb Dashboard

The Koyeb dashboard provides real-time monitoring:

| Metric | Location | Description |
|--------|----------|-------------|
| **Service status** | Dashboard → Service | Running / Unhealthy / Stopped |
| **CPU usage** | Service → Metrics | Current and historical CPU |
| **Memory usage** | Service → Metrics | RAM consumption over time |
| **Request count** | Service → Metrics | HTTP requests per minute |
| **Response time** | Service → Metrics | Average and P95 latency |
| **Logs** | Service → Logs | Real-time application logs |

### Application-Level Monitoring

The Daxelo-Kinrel API includes built-in monitoring integrations:

| Tool | Environment Variable | Purpose |
|------|---------------------|---------|
| **Sentry** | `SENTRY_DSN` | Error tracking and performance |
| **BetterStack** | `BETTERSTACK_SOURCE_TOKEN` | Log aggregation |
| **Health endpoint** | Built-in | `/api/health` returns status, DB state, uptime, memory |

### Log Levels

Control logging verbosity with `LOG_LEVEL`:

| Level | Output |
|-------|--------|
| `debug` | Everything — verbose, for development only |
| `info` | Standard operational logs (recommended for production) |
| `warn` | Only warnings and errors |
| `error` | Only errors |

### Alerts

The API includes built-in alerting thresholds:

| Variable | Default | Triggers When |
|----------|---------|---------------|
| `ERROR_RATE_ALERT_THRESHOLD` | `0.01` | Error rate exceeds 1% |
| `P99_ALERT_THRESHOLD_MS` | `2000` | P99 latency exceeds 2 seconds |

> These alerts are logged to the alerting service. Configure Sentry or BetterStack to turn them into notifications.

---

## Troubleshooting

### Build Fails — "Cannot find module '@prisma/client'"

**Cause:** Prisma Client was not generated during the Docker build.

**Fix:** Verify `Dockerfile.koyeb` includes the Prisma generate step in both stages:
```dockerfile
# Builder stage
COPY prisma ./prisma/
RUN npx prisma generate

# Runner stage
COPY prisma ./prisma/
RUN npm ci --only=production
RUN npx prisma generate
```

---

### Build Fails — "npm ci" lock file mismatch

**Cause:** `package-lock.json` is out of sync with `package.json`.

**Fix:** Regenerate the lock file locally and push:
```bash
cd server/
rm -rf node_modules package-lock.json
npm install
git add package-lock.json
git commit -m "chore: regenerate package-lock.json"
git push
```

---

### Service Starts But Health Check Fails

**Cause:** The app is listening on the wrong port, or the health check path is incorrect.

**Fix:**
1. Verify `PORT=3001` is set in Koyeb environment variables
2. Verify the Koyeb service port is set to `3001`
3. Check Koyeb logs for the startup message:
   ```
   🚀 DAXELO KINREL Server running on http://localhost:3001/api
   ```
4. Ensure the health check path is `/api/health`
5. Increase `start-period` if the nano instance is slow to boot (edit `Dockerfile.koyeb`)

---

### OOM (Out of Memory) on Nano Instance

**Cause:** The NestJS process + dependencies exceed the 512 MB RAM limit.

**Fix:**
1. Limit Node.js heap size by adding to `Dockerfile.koyeb` CMD:
   ```dockerfile
   CMD ["node", "--max-old-space-size=384", "dist/main.js"]
   ```
2. Reduce logging verbosity: set `LOG_LEVEL=warn`
3. Disable unused AI features by not setting `Z_AI_API_KEY`
4. If still OOM, upgrade to a **Micro** instance ($5/month, 1 GB RAM)

---

### WebSocket (Socket.IO) Not Working

**Cause:** Cloudflare proxy is not forwarding WebSocket connections properly.

**Fix:**
1. In Cloudflare: Ensure **WebSocket** is ON (default)
2. In Cloudflare: Ensure **Rocket Loader** is OFF
3. In Cloudflare: SSL mode must be **Full** or **Full (Strict)**
4. Test without Cloudflare proxy (grey cloud) to isolate the issue
5. Test: `wscat -c wss://api.kinrel.app/socket.io/?EIO=4&transport=websocket`

---

### Cloudflare Shows 502 Bad Gateway

**Cause:** Koyeb service is down or the DNS target is incorrect.

**Fix:**
1. Check Koyeb dashboard — is the service running and healthy?
2. Verify the CNAME record in Cloudflare points to the correct Koyeb domain
3. Check Koyeb logs for application errors
4. Test the Koyeb subdomain directly: `curl https://kinrel-api-abc123.koyeb.app/api/health`

---

### Database Connection Fails — "P1001: Can't reach database server"

**Cause:** `DATABASE_URL` is incorrect or Supabase is unreachable.

**Fix:**
1. Verify `DATABASE_URL` uses the **pooled** connection (port 6543) for runtime
2. Verify `DIRECT_URL` uses the **direct** connection (port 5432) for migrations
3. Check if Supabase has IP restrictions: Dashboard → Settings → Database → Network
4. Test from Koyeb Console: `npx prisma db push`

---

### Redis Connection Fails

**Cause:** No Redis service is available on the Koyeb free tier.

**Fix:** The app is designed to work without Redis. Simply:
1. Remove or leave `REDIS_URL` empty in environment variables
2. The app automatically falls back to in-memory caching
3. If you need Redis for production workloads, use an external Redis service (e.g., Upstash, Redis Cloud free tier) and set `REDIS_URL` to the external connection string

---

### Deployment Takes Too Long

**Cause:** The nano instance has limited CPU (0.1 vCPU), which slows Docker builds.

**Fix:**
1. Optimize the Dockerfile by minimizing layers and leveraging cache
2. Add a `.dockerignore` file to exclude unnecessary files:
   ```
   node_modules
   dist
   .git
   .env
   *.md
   ```
3. Pre-build and push to a container registry (e.g., GitHub Container Registry), then deploy from the registry instead of building on Koyeb

---

### Custom Domain Not Working

**Cause:** DNS hasn't propagated, or the CNAME target is wrong.

**Fix:**
1. Verify DNS: `dig api.kinrel.app` should resolve to Koyeb's infrastructure
2. Ensure the CNAME target matches exactly what Koyeb provides
3. Wait for DNS propagation (can take up to 48 hours, usually < 5 minutes with Cloudflare)
4. Check that Cloudflare SSL mode is set to **Full** (not **Flexible**)

---

### CORS Errors from Flutter App

**Cause:** The Flutter app's origin is not included in `CORS_ORIGINS`.

**Fix:**
1. Add all origins the Flutter app uses:
   ```
   CORS_ORIGINS=https://kinrel.app,https://www.kinrel.app,capabile://,com.daxelo.kinrel
   ```
2. For Flutter web development, add `http://localhost:8080` and `http://localhost:3001`
3. After updating environment variables, redeploy the Koyeb service

---

## Redis Consideration

The Koyeb free tier supports only **1 service**, which is used by the NestJS API. This means Redis cannot be deployed alongside the API on the free tier. Here are your options:

| Option | Cost | Setup |
|--------|------|-------|
| **No Redis (in-memory fallback)** | $0 | Leave `REDIS_URL` empty — app works fine with in-memory cache |
| **Upstash Redis** (free tier) | $0 | Create at upstash.com, set `REDIS_URL=rediss://default:xxx@upstash-redis.cloud.redislabs.com:6379` |
| **Redis Cloud** (free tier) | $0 | Create at redis.com, set `REDIS_URL=redis://default:xxx@redis-xxxxx.c1.us-east-1.ec2.cloud.redislabs.com:6379` |
| **Koyeb Micro plan + Redis** | $5/month | Upgrade to micro, deploy a second Redis service on Koyeb |

> **Recommendation:** Start without Redis (the app handles it gracefully). When you need Redis for caching or sessions, use Upstash's free tier (10K commands/day, TLS connection, global replication).

---

## Cost

| Service | Tier | Monthly Cost |
|---------|------|-------------|
| Koyeb | Free (1 nano service) | **$0** |
| Supabase | Free (500 MB DB, 50K auth users) | **$0** |
| Cloudflare | Free plan | **$0** |
| GitHub | Free (public or private repos) | **$0** |
| Let's Encrypt SSL | Free (via Koyeb) | **$0** |
| Upstash Redis | Free (optional) | **$0** |
| **Total** | | **$0/month** |

### Scaling Costs (When You Outgrow Free Tier)

| Upgrade | Cost | What You Get |
|---------|------|-------------|
| Koyeb Micro | $5/month | 1 GB RAM, 0.5 vCPU — handles ~500 concurrent users |
| Koyeb Small | $15/month | 2 GB RAM, 1 vCPU — handles ~2000 concurrent users |
| Supabase Pro | $25/month | 8 GB DB, 100K auth users, daily backups |
| Upstash Pay-as-you-go | ~$1/month | Unlimited commands, global replication |

> **When to upgrade:** The nano instance is sufficient for initial launch (~100 concurrent users). Monitor memory usage in the Koyeb dashboard — if it consistently exceeds 80%, upgrade to micro.

---

## File Reference

```
deploy/
├── KOYEB.md                  # This guide — Koyeb deployment
├── COOLIFY.md                # Coolify deployment guide (alternative)
├── DEPLOYMENT.md              # Original manual Docker deployment guide
├── koyeb-env-setup.md        # Environment variables reference for Koyeb
├── coolify-env-template.md   # Environment variables reference for Coolify
├── docker-compose.prod.yml    # Production Docker Compose (manual approach)
├── nginx/
│   └── nginx.conf             # Nginx config (not needed with Koyeb)
└── scripts/
    ├── backup.sh               # Backup script (still useful for DB)
    ├── setup-vps.sh            # VPS setup (not needed — Koyeb is managed)
    ├── deploy.sh               # Deploy script (not needed — Koyeb handles it)
    └── ssl.sh                  # SSL management (not needed — Koyeb handles it)

server/
├── Dockerfile.koyeb           # Production Dockerfile for Koyeb (this feature)
├── Dockerfile                 # Standard production Dockerfile (for VPS/Coolify)
├── .koyeb/
│   └── config.yaml            # Koyeb service configuration
├── nixpacks.toml              # Nixpacks build config (for Coolify)
├── coolify.json               # Coolify deployment reference
└── package.json               # Node.js dependencies
```

---

## Quick Start Summary

```bash
# ── Step 1: Create Koyeb account (1 min) ──────────────────
# Go to koyeb.com → Sign up with GitHub

# ── Step 2: Create service (5 min) ────────────────────────
# Dashboard → Create Service → GitHub
#   Repository: buildwith-manish/Daxelo-Kinrel
#   Branch: main
#   Build directory: server
#   Dockerfile path: Dockerfile.koyeb
#   Port: 3001
#   Instance: Nano (free)
#   Region: Frankfurt (fra)

# ── Step 3: Add environment variables (5 min) ─────────────
# Add all vars from deploy/koyeb-env-setup.md
# Minimum 15 required for first deploy

# ── Step 4: Deploy (3 min) ────────────────────────────────
# Click Deploy → Watch build logs → Wait for health check

# ── Step 5: Custom domain (2 min) ─────────────────────────
# Koyeb: Add domain api.kinrel.app
# Cloudflare: CNAME api → kinrel-api-xxx.koyeb.app (Proxied)
# Cloudflare: SSL mode → Full

# ── Step 6: Verify (1 min) ────────────────────────────────
# curl https://api.kinrel.app/api/health
# {"status":"ok","db":"connected",...}

# ── Total time: ~15 minutes ───────────────────────────────
# ── Total cost: $0/month ──────────────────────────────────
```
