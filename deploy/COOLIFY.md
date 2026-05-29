# 🚀 Daxelo-Kinrel — Coolify Deployment Guide

> **Deploy the Daxelo-Kinrel NestJS API to production in under 30 minutes using Coolify — a free, self-hosted PaaS that replaces manual Docker Compose + Nginx + SSL management.**

---

## Table of Contents

1. [Why Coolify?](#why-coolify)
2. [Architecture Overview](#architecture-overview)
3. [Coolify vs Manual Docker](#coolify-vs-manual-docker)
4. [Cost Breakdown](#cost-breakdown)
5. [Step 1: Oracle Cloud VPS Setup](#step-1-oracle-cloud-vps-setup)
6. [Step 2: Install Coolify](#step-2-install-coolify)
7. [Step 3: Coolify Setup Wizard](#step-3-coolify-setup-wizard)
8. [Step 4: Add Server as Resource](#step-4-add-server-as-resource)
9. [Step 5: Create Project & Deploy Services](#step-5-create-project--deploy-services)
10. [Step 6: Configure Domain & SSL](#step-6-configure-domain--ssl)
11. [Step 7: Configure Cloudflare DNS](#step-7-configure-cloudflare-dns)
12. [Step 8: Deploy](#step-8-deploy)
13. [Post-Deploy: Update Flutter App](#post-deploy-update-flutter-app)
14. [Environment Variables Reference](#environment-variables-reference)
15. [Ongoing Operations](#ongoing-operations)
16. [Troubleshooting](#troubleshooting)

---

## Why Coolify?

**Coolify** is an open-source, self-hosted PaaS (Platform as a Service) — think of it as your own Heroku/Vercel/Railway, running on your own server, completely free.

### The Problem with Manual Docker

Before Coolify, deploying the Daxelo-Kinrel server required:

| Task | Manual Effort |
|------|--------------|
| Install Docker + Docker Compose | SSH + run scripts |
| Write and maintain Nginx config | Manual reverse proxy setup |
| Set up SSL certificates | Generate Cloudflare Origin certs, copy to VPS, set permissions |
| Configure systemd auto-restart | Write `.service` file, `systemctl enable` |
| Run Prisma migrations manually | SSH in, set env vars, `npx prisma migrate deploy` |
| Monitor container health | `docker ps`, `docker logs`, custom scripts |
| Update the server | SSH + `git pull` + `docker compose up --build -d` |
| Rotate secrets | SSH + edit `.env` file + restart containers |
| Debug issues | SSH + dig through logs across multiple containers |

**That's 8+ manual SSH sessions and dozens of commands for every deployment cycle.**

### What Coolify Gives You

| Feature | Coolify |
|---------|---------|
| **One-click deploy** | Push to GitHub → Coolify auto-builds and deploys |
| **Auto SSL** | Let's Encrypt certificates, auto-renewed |
| **Web dashboard** | Monitor services, view logs, manage env vars from browser |
| **Built-in databases** | One-click PostgreSQL, Redis, MongoDB |
| **Zero-downtime deploys** | Rolling updates by default |
| **Auto-healing** | Restarts crashed containers automatically |
| **Terminal access** | Web-based terminal when you need SSH |
| **Multi-service orchestration** | API + Redis + DB managed together |
| **Free forever** | Self-hosted, open-source (AGPL v3) |

**Bottom line:** Coolify replaces ~200 lines of deployment scripts and manual SSH sessions with a beautiful web UI that handles everything automatically.

---

## Architecture Overview

```
┌──────────────────────────────────────────────────────────────────┐
│                        PRODUCTION ARCHITECTURE                   │
│                                                                  │
│  Flutter App (Android/iOS/Web)                                  │
│      │                                                           │
│      │  Supabase Auth (direct HTTPS from app)                   │
│      │                                                           │
│      ▼                                                           │
│  Cloudflare CDN ─── SSL Termination + DDoS Protection           │
│      │                                                           │
│      │  HTTPS (Full Strict)                                     │
│      ▼                                                           │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │          Oracle Cloud Free VPS                           │   │
│  │                                                          │   │
│  │  ┌──────────────────────────────────────────────────┐   │   │
│  │  │  Coolify (Docker Manager — port 8000)            │   │   │
│  │  │  ├── Web Dashboard: https://coolify.kinrel.app   │   │   │
│  │  │  ├── Auto SSL via Let's Encrypt                  │   │   │
│  │  │  ├── Auto-deploy from GitHub                     │   │   │
│  │  │  └── Container health monitoring                  │   │   │
│  │  └──────────────────────────────────────────────────┘   │   │
│  │                         │ manages                         │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │   │
│  │  │  NestJS API  │  │    Redis     │  │  (Optional)  │   │   │
│  │  │  Port 3001   │  │  Port 6379   │  │  PostgreSQL  │   │   │
│  │  │              │  │              │  │  (Coolify)   │   │   │
│  │  │  • REST API  │  │  • Sessions  │  │  or use      │   │   │
│  │  │  • Socket.IO │  │  • Cache     │  │  Supabase    │   │   │
│  │  │  • Prisma    │  │  • Pub/Sub   │  │  (external)  │   │   │
│  │  └──────┬───────┘  └──────────────┘  └──────────────┘   │   │
│  │         │                                                 │   │
│  └─────────┼─────────────────────────────────────────────────┘   │
│            │                                                      │
│            ▼                                                      │
│  Supabase (External — Free Tier)                                 │
│  ├── Auth (Supabase Auth — used directly by Flutter)            │
│  ├── PostgreSQL (Prisma via pooled connection, port 6543)       │
│  ├── Storage (Image/file uploads)                                │
│  └── Realtime (Optional — can use Socket.IO instead)            │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘

Request Flow:
  Flutter App
    → Cloudflare (CDN + WAF + SSL)
      → Coolify Traefik Proxy (auto reverse proxy)
        → NestJS API (port 3001)
          → Redis (caching, sessions)
          → Supabase PostgreSQL (database)
          → Cloudinary (media)
          → Firebase FCM (push notifications)
```

### How Coolify Changes the Architecture

| Before (Manual Docker) | After (Coolify) |
|------------------------|------------------|
| Nginx reverse proxy (manual config) | **Traefik** (Coolify's built-in reverse proxy, auto-configured) |
| Cloudflare Origin Certs (manual setup) | **Let's Encrypt** (auto-provisioned by Coolify via Traefik) |
| systemd service (manual `.service` file) | **Coolify's process manager** (auto-restarts, health checks) |
| Docker Compose file (manual `up -d`) | **Coolify's orchestrator** (one-click deploy) |
| SSH for all operations | **Web dashboard** + optional SSH |

---

## Coolify vs Manual Docker

| Aspect | Manual Docker Compose | Coolify |
|--------|----------------------|---------|
| **Initial setup time** | 2–3 hours (scripts + debugging) | 30–45 minutes |
| **Deployment** | `ssh` → `git pull` → `docker compose up --build -d` | Push to GitHub → auto-deploy, or click "Redeploy" |
| **SSL certificates** | Manual Cloudflare Origin cert + Nginx config | Auto Let's Encrypt via Traefik |
| **SSL renewal** | Manual (or custom cron) | Automatic (Let's Encrypt renews every 60 days) |
| **Environment variables** | SSH → `nano .env.production` → restart | Web UI → edit → save (auto-restart) |
| **Viewing logs** | `ssh` → `docker compose logs -f api` | Web UI → real-time log viewer |
| **Container monitoring** | `docker ps` + custom scripts | Dashboard with health status |
| **Scaling** | Manual `docker compose up --scale` | UI-based resource allocation |
| **Database management** | External only (Supabase) or manual PostgreSQL | One-click PostgreSQL, Redis, MongoDB |
| **Rollback** | `docker compose down` + manual revert | Click "Redeploy" previous version |
| **Team access** | Share SSH keys | Multiple users with role-based access |
| **Cost** | $0 (your time: $$$) | $0 (your time: $) |
| **Maintenance overhead** | High — you own all infra code | Low — Coolify handles the plumbing |

---

## Cost Breakdown

| Service | Tier | Monthly Cost |
|---------|------|-------------|
| Oracle Cloud VM | Always Free (1 GB RAM, 1 OCPU) | **$0** |
| Coolify | Self-hosted, open-source | **$0** |
| Cloudflare | Free plan | **$0** |
| Supabase | Free (500 MB DB, 1 GB storage, 50K auth users) | **$0** |
| Let's Encrypt SSL | Free | **$0** |
| GitHub | Free (public or private repos) | **$0** |
| **Total** | | **$0/month** |

> 💡 **When to upgrade:** Supabase Free tier is sufficient for initial launch (~1,000 users). When you hit limits, upgrade to Supabase Pro ($25/month). Oracle Cloud Always Free VM can handle ~100 concurrent users comfortably.

---

## Step 1: Oracle Cloud VPS Setup

### 1.1 Create the VM Instance

1. Go to [Oracle Cloud Console](https://cloud.oracle.com/) → **Compute → Instances**
2. Click **Create Instance**
3. Configure:
   - **Name**: `kinrel-coolify`
   - **Image**: Ubuntu 22.04 (Canonical) — or 24.04
   - **Shape**: VM.Standard.E2.1.Micro (Always Free)
   - **Boot volume**: 47 GB (default)
4. **SSH Key**: Upload your public key or generate a new one
5. Click **Create**

> ⚠️ Save the SSH private key! You'll need it to connect.

### 1.2 Configure Oracle Cloud Security List

Oracle Cloud blocks most traffic by default. Open the required ports:

1. Go to **Networking → Virtual Cloud Networks**
2. Click your VCN → **Security Lists** → Default Security List
3. Add **Ingress Rules**:

| Source | Protocol | Port | Description |
|--------|----------|------|-------------|
| 0.0.0.0/0 | TCP | 22 | SSH access |
| 0.0.0.0/0 | TCP | 80 | HTTP (Coolify/Let's Encrypt challenge) |
| 0.0.0.0/0 | TCP | 443 | HTTPS |
| 0.0.0.0/0 | TCP | 8000 | Coolify Dashboard (optional — can restrict to your IP) |

> 💡 **Security tip:** For port 8000, consider restricting the source to your own IP address instead of `0.0.0.0/0`. You can always access Coolify via SSH tunnel if needed.

### 1.3 Connect to the VPS

```bash
ssh -i /path/to/ssh-key ubuntu@<VPS_PUBLIC_IP>
```

> The default user is `ubuntu` for Ubuntu images. For Oracle Linux, use `opc`.

### 1.4 Open OS-Level Firewall (if needed)

Oracle Cloud's Ubuntu images sometimes have `iptables` rules that block traffic even after opening Security List ports:

```bash
sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 443 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 8000 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 22 -j ACCEPT
sudo netfilter-persistent save
```

### 1.5 Add Swap (Essential for 1 GB RAM VPS)

```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Make it persistent across reboots
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Verify
free -h
```

### 1.6 Update the System

```bash
sudo apt-get update && sudo apt-get upgrade -y
```

---

## Step 2: Install Coolify

Coolify installs with a single command. It automatically sets up Docker, Traefik (reverse proxy), and the Coolify dashboard.

### 2.1 Run the Installer

```bash
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash
```

This script:
1. Installs Docker Engine (if not already installed)
2. Installs Docker Compose v2
3. Pulls Coolify images
4. Starts Coolify on port 8000
5. Sets up auto-start on boot

**Installation takes about 3–5 minutes.** You'll see output like:

```
✅ Docker is installed
✅ Docker Compose is installed
✅ Pulling Coolify images...
✅ Starting Coolify...
✅ Coolify is running!
```

### 2.2 Verify Coolify is Running

```bash
sudo docker ps | grep coolify
```

You should see Coolify containers running. The dashboard is accessible at:

```
http://<VPS_PUBLIC_IP>:8000
```

> 💡 If you can't access it, check that port 8000 is open in both the Oracle Cloud Security List **and** the OS firewall (see Step 1.4).

---

## Step 3: Coolify Setup Wizard

### 3.1 Access the Dashboard

Open your browser and navigate to:

```
http://<VPS_PUBLIC_IP>:8000
```

*[Screenshot description: Coolify setup wizard — white background, Coolify logo at top, "Register" heading, form with email and password fields, blue "Register" button]*

### 3.2 Create Admin Account

Fill in:
- **Email**: Your admin email (e.g., `admin@kinrel.app`)
- **Password**: Strong password (min 8 characters, use a password manager)

Click **Register**.

> ⚠️ **Save these credentials securely.** There is no password reset without database access.

### 3.3 Dashboard Overview

After registration, you'll see the Coolify dashboard:

*[Screenshot description: Clean dashboard with sidebar navigation — Servers, Projects, Settings. Main area shows "No servers yet" with a call-to-action to add one]*

---

## Step 4: Add Server as Resource

Coolify needs to know which server to deploy to. Since Coolify is running on the same VPS, you'll add the **local server**.

### 4.1 Add Local Server

1. In the sidebar, click **Servers**
2. Click **Add Server**
3. Select **Localhost** (the server Coolify is running on)

*[Screenshot description: "Add Server" modal with two options — "Localhost" (recommended) and "Remote Server". Localhost is highlighted.]*

4. Coolify will verify the connection and install its agent on the server
5. Once connected, you'll see the server listed with a green **Connected** status

### 4.2 Verify Server Resources

Click on the server to view its resources:

*[Screenshot description: Server detail page showing CPU, Memory, Disk usage. Docker Engine status: "Running". Available resources listed.]*

You should see:
- **Docker Engine**: Running ✅
- **CPU**: 1 OCPU
- **Memory**: ~1 GB (2 GB with swap)
- **Disk**: ~47 GB

---

## Step 5: Create Project & Deploy Services

### 5.1 Create a New Project

1. Click **Projects** in the sidebar
2. Click **Add Project**
3. Name it: `Daxelo-Kinrel`
4. Click **Save**

*[Screenshot description: "New Project" form with project name field and save button]*

### 5.2 Add the NestJS API Service

Inside the `Daxelo-Kinrel` project:

1. Click **Add Resource** → **Application**
2. Configure the application:

#### Source Configuration

| Field | Value |
|-------|-------|
| **Name** | `kinrel-api` |
| **Server** | Select your localhost server |
| **Source** | **GitHub** (recommended) or **Git** |
| **Repository** | `buildwith-manish/Daxelo-Kinrel` |
| **Branch** | `main` |
| **Root Directory** | `server` ← **CRITICAL: Must be `server`, not `/`** |

*[Screenshot description: Source configuration form showing GitHub selected, repository dropdown with "buildwith-manish/Daxelo-Kinrel", branch "main", and root directory "server" highlighted]*

> ⚠️ **Root Directory** is the most important setting. The repo contains both the Flutter app and the NestJS server. Setting root directory to `server/` tells Coolify to build only the server — not the entire monorepo.

#### Build Configuration

| Field | Value |
|-------|-------|
| **Build Pack** | **Nixpacks** (recommended) or **Docker** |
| **Nixpacks Plan** | Auto-detected from `nixpacks.toml` |

*[Screenshot description: Build pack selector with "Nixpacks" and "Docker" options. Nixpacks is selected with a note "Uses nixpacks.toml" if present]*

**Why Nixpacks?**
- Reads our `server/nixpacks.toml` for custom build steps
- Handles `npm ci`, `npx prisma generate`, and `npm run build` automatically
- Produces an optimized production image without needing a custom Dockerfile

**Why Docker works too?**
- Our existing `server/Dockerfile` is a multi-stage production-ready image
- Select "Docker" as build pack to use it
- Same result, just a different build path

#### Port Configuration

| Field | Value |
|-------|-------|
| **Port** | `3001` |

> Coolify needs to know which port the app listens on so Traefik can route traffic to it.

#### Environment Variables

Click **Environment Variables** and add all variables from the [Environment Variables Reference](#environment-variables-reference) section below, or see `deploy/coolify-env-template.md` for the complete list with instructions.

**Minimum required for first deploy:**

```env
NODE_ENV=production
PORT=3001
API_PREFIX=api
FRONTEND_URL=https://kinrel.app
DATABASE_URL=postgresql://postgres.REF:PASS@aws-0-REGION.pooler.supabase.com:6543/postgres
DIRECT_URL=postgresql://postgres:PASS@db.REF.supabase.co:5432/postgres
JWT_ACCESS_SECRET=<generate with: openssl rand -hex 32>
JWT_ACCESS_EXPIRATION=15m
JWT_REFRESH_SECRET=<generate with: openssl rand -hex 32>
JWT_REFRESH_EXPIRATION=7d
SUPABASE_URL=https://promxswvsnvilplmrtsj.supabase.co
SUPABASE_ANON_KEY=<your-anon-key>
SUPABASE_JWT_SECRET=<your-jwt-secret>
SUPABASE_SERVICE_ROLE_KEY=<your-service-role-key>
CORS_ORIGINS=https://kinrel.app,https://www.kinrel.app,capabile://,com.daxelo.kinrel
REDIS_URL=redis://kinrel-redis:6379
```

*[Screenshot description: Environment variables editor with key-value pairs. Each row has key, value, and an eye icon to toggle secret visibility. Several rows are marked as secrets (values hidden with dots)]*

> 💡 **Bulk import:** Click "Edit in bulk" and paste all `KEY=VALUE` pairs at once from your `.env.production` file.

#### Health Check

| Field | Value |
|-------|-------|
| **Health Check Path** | `/api/health` |
| **Health Check Interval** | `30` seconds |
| **Health Check Timeout** | `5` seconds |
| **Start Period** | `30` seconds |
| **Retries** | `3` |

Coolify will use this to determine if the API is healthy. The `/api/health` endpoint returns `{"status":"ok","db":"connected"}`.

### 5.3 Add Redis Service

Instead of running Redis in a separate Docker container manually, use Coolify's one-click service:

1. In the `Daxelo-Kinrel` project, click **Add Resource** → **Service**
2. Search for **Redis**
3. Select **Redis** from the service templates

*[Screenshot description: Service templates gallery with search bar. "Redis" card is visible with description "In-memory data structure store, used as a database, cache, and message broker."]*

4. Configure:

| Field | Value |
|-------|-------|
| **Name** | `kinrel-redis` |
| **Server** | Your localhost server |

5. Click **Deploy**

Redis will be available at `redis://kinrel-redis:6379` within the Coolify Docker network.

> **IMPORTANT:** The Redis service name (`kinrel-redis`) must match the hostname in your `REDIS_URL` environment variable. If you name it differently, update `REDIS_URL` accordingly.

### 5.4 PostgreSQL (Optional — Using External Supabase Instead)

We recommend using **Supabase PostgreSQL** externally (free, managed, with backups). However, if you want a local PostgreSQL:

1. In the `Daxelo-Kinrel` project, click **Add Resource** → **Database**
2. Select **PostgreSQL**
3. Configure and deploy

Then update `DATABASE_URL` and `DIRECT_URL` to point to the local PostgreSQL instance.

> **Recommendation:** Stick with Supabase for production. It gives you free managed PostgreSQL with automatic backups, connection pooling, and a SQL editor.

---

## Step 6: Configure Domain & SSL

### 6.1 Set the Domain for the API

1. Go to your `kinrel-api` application in Coolify
2. Click **Domains**
3. Add domain: `api.kinrel.app`

*[Screenshot description: Domain configuration screen. Input field showing "api.kinrel.app" with a toggle for HTTPS/SSL. A green "Let's Encrypt" badge indicates auto-SSL is active.]*

4. Enable **HTTPS** — Coolify will automatically provision a Let's Encrypt certificate
5. Click **Save**

Coolify's Traefik reverse proxy will:
- Listen on ports 80/443 for `api.kinrel.app`
- Auto-redirect HTTP → HTTPS
- Auto-provision and auto-renew Let's Encrypt SSL certificates
- Route all traffic to the NestJS API on port 3001

### 6.2 Set the Domain for Coolify Dashboard (Optional but Recommended)

Secure the Coolify admin dashboard with its own domain:

1. In Coolify, go to **Settings → Instance Settings**
2. Set the domain: `coolify.kinrel.app`
3. Enable HTTPS with Let's Encrypt

This way:
- `api.kinrel.app` → NestJS API
- `coolify.kinrel.app` → Coolify Dashboard

> 🔒 **Security:** Protect the Coolify dashboard with Cloudflare Access or restrict port 8000 to your IP address.

### 6.3 How Coolify's SSL Works

```
Client Request
    │
    │  HTTPS (TLS 1.3)
    ▼
Traefik (Coolify's Reverse Proxy)
    │
    │  Auto-provisions Let's Encrypt cert for api.kinrel.app
    │  Auto-renews 30 days before expiry
    │  Handles HTTP → HTTPS redirect
    │
    │  HTTP (plain, internal)
    ▼
NestJS API (port 3001 inside container)
```

**No manual certificate management. No Cloudflare Origin certs. No Nginx.** Traefik + Let's Encrypt handles everything.

---

## Step 7: Configure Cloudflare DNS

### 7.1 Add Domain to Cloudflare

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com/)
2. Click **Add Site** → Enter `kinrel.app`
3. Select **Free Plan**
4. Update nameservers at your domain registrar as Cloudflare instructs

### 7.2 Configure DNS Records

Go to **DNS → Records** and add:

| Type | Name | Content | Proxy | TTL |
|------|------|---------|-------|-----|
| A | `api` | `<VPS_PUBLIC_IP>` | ☁️ Proxied | Auto |
| A | `coolify` | `<VPS_PUBLIC_IP>` | ☁️ Proxied | Auto |
| A | `@` | `<VPS_PUBLIC_IP>` | ☁️ Proxied | Auto |
| CNAME | `www` | `kinrel.app` | ☁️ Proxied | Auto |

> ☁️ **Proxied** (orange cloud) means traffic goes through Cloudflare CDN — DDoS protection, WAF, and caching.

### 7.3 Configure SSL/TLS

Go to **SSL/TLS → Overview**:
- Set mode to **Full** (not Full Strict)

> **Why Full instead of Full Strict?** Coolify uses Let's Encrypt certificates, which are publicly trusted. However, with Cloudflare's **Full** mode, Cloudflare validates the origin connection but doesn't need to verify the full CA chain — this is simpler and works perfectly with Let's Encrypt. If you want maximum security, use **Full (Strict)** — it works too since Let's Encrypt certs are valid CA-signed certificates.

### 7.4 Additional Cloudflare Settings

| Setting | Location | Value |
|---------|----------|-------|
| Always Use HTTPS | SSL/TLS → Edge Certificates | ✅ ON |
| Minimum TLS Version | SSL/TLS → Edge Certificates | TLS 1.2 |
| Auto Minify | Speed → Optimization | ✅ All |
| Brotli | Speed → Optimization | ✅ ON |
| Rocket Loader | Speed → Optimization | ❌ OFF (can break WebSocket) |
| Security Level | Security → Settings | Medium |
| WebSocket | Network → WebSockets | ✅ ON (default) |

### 7.5 Configure WebSocket Support

Cloudflare supports WebSocket by default on all plans. Just ensure:
1. **Rocket Loader** is OFF
2. **SSL mode** is Full or Full (Strict)
3. The Cloudflare timeout for WebSocket is set appropriately (default 100 seconds on Free plan)

For the Socket.IO path (`/socket.io/`), Cloudflare proxies it automatically — no special page rules needed.

---

## Step 8: Deploy

### 8.1 First Deployment

1. Go to **Projects → Daxelo-Kinrel → kinrel-api**
2. Click **Deploy** (big green button)

*[Screenshot description: Application detail page with deployment status "Not deployed". Large green "Deploy" button at top right. Build logs area is empty.]*

3. Watch the build logs in real-time:

*[Screenshot description: Real-time build log output scrolling. Shows phases: "Installing dependencies...", "Running npm ci...", "Generating Prisma client...", "Building NestJS...", "Starting application on port 3001..."]*

**Build process (Nixpacks):**
```
[1/3] Install:  npm ci --ignore-scripts
                 npx prisma generate
[2/3] Build:    npm run build
[3/3] Start:    node dist/main
```

**Build process (Docker):**
```
Building Docker image from server/Dockerfile...
Step 1/15: FROM node:20-alpine AS builder
...
Step 15/15: CMD ["node", "dist/main"]
```

### 8.2 Verify Deployment

Once the deployment completes, check:

1. **Coolify Dashboard** — Application status should show **Running** ✅
2. **Health Check** — Click the health check indicator (should be green)
3. **Manual check:**

```bash
# From the VPS
curl http://localhost:3001/api/health

# Expected response:
# {"status":"ok","db":"connected","uptime":...}

# From your local machine (after DNS propagates)
curl https://api.kinrel.app/api/health
```

4. **WebSocket test:**

```bash
# Install wscat if needed
npm install -g wscat

# Test WebSocket connection
wscat -c wss://api.kinrel.app/socket.io/?EIO=4&transport=websocket
```

### 8.3 Enable Auto-Deploy from GitHub

To automatically deploy when you push to `main`:

1. Go to **kinrel-api → Configuration → Source**
2. Enable **Auto Deploy** on push to `main`
3. Coolify will watch your GitHub repo and auto-deploy on every push

> 💡 You can also set up **Deploy on PR** to preview changes before merging.

### 8.4 Deploy Redis

If you haven't deployed Redis yet (from Step 5.3):

1. Go to **Projects → Daxelo-Kinrel → kinrel-redis**
2. Click **Deploy**
3. Verify: `docker exec -it kinrel-redis redis-cli ping` → should return `PONG`

---

## Post-Deploy: Update Flutter App

Your Flutter app currently may point to `daxelo-kinrel-server.onrender.com` or a development URL. Update it to use the new Coolify-deployed API:

### Option A: Change in `env_config.dart` (Recommended)

In `Daxelo-Kinrel-App/lib/core/config/env_config.dart`:

```dart
// Before
static const String apiBaseUrl = 'https://daxelo-kinrel-server.onrender.com';

// After
static const String apiBaseUrl = 'https://api.kinrel.app';
```

### Option B: Update codemagic.yaml

```yaml
# Before
API_BASE_URL: https://daxelo-kinrel-server.onrender.com

# After
API_BASE_URL: https://api.kinrel.app
```

### Option C: Use Firebase Remote Config (No code change needed)

If your Flutter app reads the API URL from Firebase Remote Config:

1. Go to Firebase Console → Remote Config
2. Update `API_BASE_URL` parameter to `https://api.kinrel.app`
3. Publish changes — takes effect immediately for all users

### Important: CORS Origins

Ensure `CORS_ORIGINS` in Coolify's environment variables includes all origins the Flutter app sends requests from:

```
CORS_ORIGINS=https://kinrel.app,https://www.kinrel.app,capabile://,com.daxelo.kinrel
```

### Important: Supabase Auth Redirect URLs

Update Supabase to allow the new domain:

1. Go to **Supabase Dashboard → Authentication → URL Configuration**
2. Add site URL: `https://kinrel.app`
3. Add redirect URLs:
   - `https://kinrel.app/**`
   - `capabile://**`
   - `com.daxelo.kinrel://**`

---

## Environment Variables Reference

For the complete list of environment variables with detailed instructions on where to find each value, see **[`deploy/coolify-env-template.md`](./coolify-env-template.md)**.

### Minimum Required (First Deploy)

These 15 variables are all you need to get the API running:

```env
# Server
NODE_ENV=production
PORT=3001
API_PREFIX=api
FRONTEND_URL=https://kinrel.app

# Database
DATABASE_URL=postgresql://postgres.REF:PASS@pooler.supabase.com:6543/postgres
DIRECT_URL=postgresql://postgres:PASS@db.REF.supabase.co:5432/postgres

# Auth
JWT_ACCESS_SECRET=<64-char hex>
JWT_ACCESS_EXPIRATION=15m
JWT_REFRESH_SECRET=<64-char hex>
JWT_REFRESH_EXPIRATION=7d

# Supabase
SUPABASE_URL=https://promxswvsnvilplmrtsj.supabase.co
SUPABASE_ANON_KEY=<your-key>
SUPABASE_JWT_SECRET=<your-secret>
SUPABASE_SERVICE_ROLE_KEY=<your-key>

# Redis & CORS
CORS_ORIGINS=https://kinrel.app,https://www.kinrel.app,capabile://,com.daxelo.kinrel
REDIS_URL=redis://kinrel-redis:6379
```

### Optional (Add Incrementally)

| Category | Variables | Enables |
|----------|-----------|---------|
| **Google OAuth** | `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_CALLBACK_URL` | Social sign-in |
| **AI Features** | `Z_AI_API_KEY` | AI Chat, AI Voice, AI Cards, Content Moderation |
| **Cloudinary** | `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET` | Image uploads and transforms |
| **Email** | `SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS` | Transactional emails, password reset |
| **Razorpay** | `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET` | India payments (INR) |
| **Stripe** | `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` | International payments |
| **Sentry** | `SENTRY_DSN`, `BETTERSTACK_SOURCE_TOKEN` | Error tracking, log aggregation |
| **Firebase** | `FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY` | Push notifications |
| **Logging** | `LOG_LEVEL`, `LOG_DIR`, `ERROR_RATE_ALERT_THRESHOLD`, `P99_ALERT_THRESHOLD_MS` | Structured logging + alerting |

---

## Ongoing Operations

### How to Update the Server

**Auto-deploy (recommended):**
1. Push code to the `main` branch on GitHub
2. Coolify detects the change and auto-deploys

**Manual deploy:**
1. Go to Coolify Dashboard → `kinrel-api`
2. Click **Redeploy**

**Rollback:**
1. Go to Coolify Dashboard → `kinrel-api` → **Deployments**
2. Find the previous working deployment
3. Click **Redeploy this version**

### View Logs

1. Go to Coolify Dashboard → `kinrel-api`
2. Click **Logs** tab
3. Real-time logs stream automatically

Or via SSH:
```bash
sudo docker logs kinrel-api --tail 100 -f
```

### Run Prisma Migrations

When you make schema changes, run migrations through Coolify's terminal:

1. Go to Coolify Dashboard → `kinrel-api` → **Terminal**
2. Run:

```bash
npx prisma migrate deploy
```

Or via SSH:
```bash
docker exec -it kinrel-api npx prisma migrate deploy
```

### Manage Environment Variables

1. Go to Coolify Dashboard → `kinrel-api` → **Environment Variables**
2. Edit, add, or remove variables
3. Click **Save** — Coolify will prompt to redeploy if needed

### Monitor Service Health

The Coolify dashboard shows real-time health status for all services:

- 🟢 **Green**: Service is healthy
- 🟡 **Yellow**: Service is starting or degraded
- 🔴 **Red**: Service is down or unhealthy

### Backup

Supabase handles database backups automatically. For Redis data:

```bash
# Via Coolify terminal on kinrel-redis
redis-cli SAVE

# Copy the dump file
docker cp kinrel-redis:/data/dump.rdb ./redis-backup-$(date +%Y%m%d).rdb
```

---

## Troubleshooting

### ❌ Build Fails — "Cannot find module '@prisma/client'"

**Cause:** Prisma Client wasn't generated during the build.

**Fix:** Ensure `server/nixpacks.toml` includes the Prisma generate step:

```toml
[phases.install]
cmds = [
    "npm ci --ignore-scripts",
    "npx prisma generate",
]
```

If using Docker build pack, ensure the Dockerfile has `RUN npx prisma generate`.

---

### ❌ Build Fails — "npm ci" fails with lock file mismatch

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

### ❌ App Starts But Health Check Fails

**Cause:** The health check is hitting the wrong port or path.

**Fix:**
1. Verify `PORT=3001` is set in Coolify environment variables
2. Verify the health check path is `/api/health`
3. Check Coolify logs for the actual startup message:
   ```
   🚀 DAXELO KINREL Server running on http://localhost:3001/api
   ```

---

### ❌ WebSocket (Socket.IO) Not Working

**Cause:** Cloudflare or Traefik is not proxying WebSocket connections.

**Fix:**
1. In Cloudflare: Ensure **Rocket Loader** is OFF
2. In Cloudflare: SSL mode must be **Full** or **Full (Strict)**
3. In Coolify: Traefik auto-handles WebSocket — no special config needed
4. Test: `wscat -c wss://api.kinrel.app/socket.io/?EIO=4&transport=websocket`

---

### ❌ Cloudflare Shows 502 Bad Gateway

**Cause:** Traefik can't reach the NestJS container, or the container is not running.

**Fix:**
1. Check Coolify Dashboard — is `kinrel-api` running?
2. Check Coolify logs for the API container
3. Verify the API responds locally: `curl http://localhost:3001/api/health`
4. If using Cloudflare SSL **Full (Strict)**, ensure the Let's Encrypt cert is valid (Coolify Dashboard → `kinrel-api` → Domains → SSL status)

---

### ❌ Redis Connection Refused

**Cause:** `REDIS_URL` hostname doesn't match the Coolify service name.

**Fix:**
1. In Coolify, check the Redis service name (e.g., `kinrel-redis`)
2. Update `REDIS_URL` to match: `redis://kinrel-redis:6379`
3. Ensure both API and Redis are in the same Coolify project (same Docker network)

---

### ❌ Prisma Migration Fails — "P1001: Can't reach database server"

**Cause:** `DATABASE_URL` is incorrect or Supabase is not reachable from the VPS.

**Fix:**
1. Verify `DATABASE_URL` uses the **pooled** connection (port 6543)
2. Verify `DIRECT_URL` uses the **direct** connection (port 5432) for migrations
3. Test from the VPS:
   ```bash
   docker exec -it kinrel-api npx prisma db push --preview-feature
   ```
4. Check if Supabase has IP restrictions (Project Settings → Database → Network)

---

### ❌ Oracle Cloud Firewall Blocks Traffic

**Cause:** Oracle Cloud has **two** firewalls — Security List (VCN level) and iptables (OS level).

**Fix:**
```bash
# Check iptables
sudo iptables -L -n

# Open ports at OS level
sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 443 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 8000 -j ACCEPT

# Persist rules
sudo netfilter-persistent save
```

Also verify the **Security List** in Oracle Cloud Console (see Step 1.2).

---

### ❌ Out of Memory (OOM) on 1 GB VPS

**Cause:** NestJS + Redis + Coolify + Traefik competing for limited RAM.

**Fix:**
1. Ensure swap is configured (Step 1.5)
2. Limit Coolify's resource usage in Settings
3. Set Redis max memory: `--maxmemory 128mb --maxmemory-policy allkeys-lru`
4. Set Node.js memory limit: add `--max-old-space-size=256` to the start command
5. Monitor: `free -h` and `docker stats`

---

### ❌ Let's Encrypt Certificate Fails to Provision

**Cause:** Domain DNS hasn't propagated, or port 80 is blocked.

**Fix:**
1. Verify DNS: `dig api.kinrel.app` should resolve to your VPS IP
2. Ensure port 80 is open (Let's Encrypt HTTP-01 challenge needs it)
3. If using Cloudflare proxy, temporarily set DNS to **DNS Only** (grey cloud) for initial cert provisioning
4. Check Coolify logs for Traefik ACME errors

---

### ❌ Coolify Dashboard Not Accessible

**Cause:** Port 8000 is blocked or Coolify container is down.

**Fix:**
```bash
# Check if Coolify is running
sudo docker ps | grep coolify

# Restart Coolify
cd /data/coolify/source
sudo docker compose restart

# Check logs
sudo docker compose logs -f coolify
```

If port 8000 is blocked, use an SSH tunnel:
```bash
ssh -L 8000:localhost:8000 -i /path/to/key ubuntu@<VPS_IP>
# Then access http://localhost:8000 in your browser
```

---

## File Reference

```
deploy/
├── COOLIFY.md                  # This guide — Coolify deployment
├── DEPLOYMENT.md               # Original manual Docker deployment guide
├── coolify-env-template.md     # Environment variables quick reference
├── docker-compose.prod.yml     # Production Docker Compose (manual approach)
├── .env.production.template    # Env template (manual approach)
├── nginx/
│   ├── nginx.conf              # Nginx config (not needed with Coolify)
│   └── conf.d/.gitkeep
├── scripts/
│   ├── setup-vps.sh            # VPS setup (not needed — Coolify handles it)
│   ├── deploy.sh               # Deploy script (not needed — Coolify handles it)
│   ├── backup.sh               # Backup script (still useful)
│   └── ssl.sh                  # SSL management (not needed — Coolify + Let's Encrypt)
├── systemd/
│   └── kinrel.service          # Auto-start (not needed — Coolify handles it)

server/
├── nixpacks.toml               # Nixpacks build config for Coolify ✨ NEW
├── coolify.json                # Coolify deployment reference ✨ NEW
├── Dockerfile                  # Multi-stage production Dockerfile (alternative to Nixpacks)
└── .env.example                # Development env template
```

---

## Quick Start Summary

```bash
# ── Step 1: Create Oracle Cloud VPS (5 min) ──────────────
# Create VM, open ports 22/80/443/8000, add 2GB swap

# ── Step 2: Install Coolify (5 min) ──────────────────────
ssh ubuntu@<VPS_IP>
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash

# ── Step 3: Setup Coolify (2 min) ────────────────────────
# Open http://<VPS_IP>:8000 → Create admin account

# ── Step 4: Add server (1 min) ───────────────────────────
# Dashboard → Servers → Add Localhost

# ── Step 5: Create project + services (10 min) ──────────
# Project: Daxelo-Kinrel
#   → Application: kinrel-api (GitHub repo, root dir: server/, build: Nixpacks)
#   → Service: kinrel-redis (one-click Redis)
#   → Add env vars from coolify-env-template.md

# ── Step 6: Configure domain (3 min) ────────────────────
# Coolify: Add domain api.kinrel.app → Auto SSL via Let's Encrypt

# ── Step 7: Cloudflare DNS (2 min) ──────────────────────
# A record: api → <VPS_IP> (Proxied)
# SSL mode: Full

# ── Step 8: Deploy! (2 min) ─────────────────────────────
# Click "Deploy" → Watch build logs → Verify health check

# ── Total time: ~30 minutes ──────────────────────────────
# ── Total cost: $0/month ─────────────────────────────────
```

---

## Migration from Manual Docker

If you're currently running the manual Docker Compose setup from `DEPLOYMENT.md`:

1. **Stop the old stack:**
   ```bash
   cd /opt/kinrel/repo
   docker compose -f deploy/docker-compose.prod.yml down
   ```

2. **Free up ports:** The old stack uses ports 80, 443, 3001, 6379. Make sure they're released:
   ```bash
   sudo lsof -i :80 -i :443 -i :3001 -i :6379
   ```

3. **Install Coolify** (Step 2) — it will take over ports 80/443 via Traefik

4. **Configure Coolify** (Steps 3–8) — reuse the same env vars from `.env.production`

5. **Update DNS** if needed — same IP, same domain, just different reverse proxy

6. **Remove old configs** (optional):
   ```bash
   sudo systemctl disable kinrel  # Remove old systemd service
   sudo rm /etc/systemd/system/kinrel.service
   ```

Your existing `.env.production` file contains all the values you need — just copy-paste them into Coolify's environment variable editor.

---

> **Questions?** Check the [Coolify Documentation](https://coolify.io/docs) or [Coolify GitHub](https://github.com/coollabsio/coolify) for additional help.
