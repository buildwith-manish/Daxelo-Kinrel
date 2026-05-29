# 🚀 Daxelo-Kinrel — Production Deployment Guide

## Architecture Overview

```
Flutter App  ──────────────────────────────────────────────┐
    │                                                      │
    │  Supabase Auth (direct from app)                     │
    ▼                                                      │
Cloudflare CDN ─── SSL Termination + DDoS Protection       │
    │                                                      │
    │  HTTPS (Full Strict)                                 │
    ▼                                                      │
Oracle Cloud Free VPS                                      │
    ├── Nginx Reverse Proxy (80/443)                       │
    │   ├── /api/* ────► NestJS API                        │
    │   └── /socket.io/* ──► WebSocket                    │
    │                                                      │
    ├── NestJS API (Docker, port 3001)                     │
    │   ├── JWT Auth (NestJS + Supabase)                   │
    │   ├── Prisma ORM                                     │
    │   └── Socket.IO Gateway                              │
    │                                                      │
    └── Redis (Docker, port 6379)                          │
                                                           │
Supabase (External)  ◄─────────────────────────────────────┘
 ├── Auth (Supabase Auth — used directly by Flutter)
 ├── PostgreSQL (Prisma via pooled connection)
 ├── Storage (Image/file uploads)
 └── Realtime (Optional — can use Socket.IO instead)
```

---

## Prerequisites

| Requirement | Details |
|---|---|
| **Oracle Cloud Free Tier** | Always Free AMD VM (1 GB RAM, 1 OCPU, 0.48 Gbps network) |
| **Domain Name** | `kinrel.app` (or your custom domain) |
| **Cloudflare Account** | Free plan works — acts as DNS + CDN + SSL |
| **Supabase Project** | Already set up at `promxswvsnvilplmrtsj` |
| **GitHub Repo** | `buildwith-manish/Daxelo-Kinrel` |

---

## Step 1: Oracle Cloud VPS Setup

### 1.1 Create the VM Instance

1. Go to [Oracle Cloud Console](https://cloud.oracle.com/) → Compute → Instances
2. Click **Create Instance**
3. Configure:
   - **Name**: `kinrel-server`
   - **Image**: Ubuntu 22.04 (Canonical)
   - **Shape**: VM.Standard.E2.1.Micro (Always Free)
   - **Boot volume**: 47 GB (default)
4. **SSH Key**: Upload your public key or generate a new one
5. Click **Create**

> ⚠️ Save the SSH private key! You'll need it to connect.

### 1.2 Configure Oracle Cloud Security List

By default, Oracle Cloud blocks most traffic. You need to open ports:

1. Go to **Networking → Virtual Cloud Networks**
2. Click your VCN → **Security Lists** → Default Security List
3. Add **Ingress Rules**:

| Source | Protocol | Port | Description |
|--------|----------|------|-------------|
| 0.0.0.0/0 | TCP | 22 | SSH |
| 0.0.0.0/0 | TCP | 80 | HTTP |
| 0.0.0.0/0 | TCP | 443 | HTTPS |

### 1.3 Connect to the VPS

```bash
ssh -i /path/to/ssh-key ubuntu@<VPS_PUBLIC_IP>
```

> 💡 The default user is `ubuntu` for Ubuntu images. For Oracle Linux, use `opc`.

### 1.4 Run the VPS Setup Script

```bash
# Clone the repository
sudo apt-get update && sudo apt-get install -y git
git clone https://github.com/buildwith-manish/Daxelo-Kinrel.git /opt/kinrel/repo

# Run the VPS setup script
sudo bash /opt/kinrel/repo/deploy/scripts/setup-vps.sh
```

This script installs:
- ✅ Docker Engine + Docker Compose v2
- ✅ UFW Firewall (ports 22, 80, 443)
- ✅ 2GB Swap file (essential for 1GB RAM VPS)
- ✅ Self-signed SSL certificate for Cloudflare
- ✅ Cloudflare Origin Pull CA certificate
- ✅ Kernel optimizations for production
- ✅ Directory structure at `/opt/kinrel/`

---

## Step 2: Configure Environment Variables

```bash
# Copy the template
cp /opt/kinrel/repo/deploy/.env.production.template /opt/kinrel/.env.production

# Edit with your production values
nano /opt/kinrel/.env.production
```

### 2.1 Required Variables (MUST fill in)

| Variable | How to get it |
|----------|---------------|
| `DATABASE_URL` | Supabase Dashboard → Settings → Database → Connection string (pooled, port 6543) |
| `DIRECT_URL` | Same but with port 5432 (direct connection) |
| `JWT_ACCESS_SECRET` | Run: `openssl rand -hex 32` |
| `JWT_REFRESH_SECRET` | Run: `openssl rand -hex 32` |
| `SUPABASE_ANON_KEY` | Supabase Dashboard → Settings → API → anon public |
| `SUPABASE_JWT_SECRET` | Supabase Dashboard → Settings → API → JWT Secret |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase Dashboard → Settings → API → service_role |

### 2.2 Important Notes

- **`PORT=3001`** — Do NOT change this! It must match the Docker mapping.
- **`REDIS_URL=redis://redis:6379`** — Uses Docker service name, not localhost.
- **`CORS_ORIGINS`** — Must include your web domain + mobile app schemes.
- **`DATABASE_URL`** — Must use the **pooled** connection (port 6543) for runtime.
- **`DIRECT_URL`** — Must use the **direct** connection (port 5432) for migrations only.

---

## Step 3: Cloudflare Configuration

### 3.1 Add Domain to Cloudflare

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com/)
2. Click **Add Site** → Enter `kinrel.app`
3. Select **Free Plan**
4. Cloudflare will show you nameservers — update them at your domain registrar

### 3.2 Configure DNS Records

Go to **DNS → Records** and add:

| Type | Name | Content | Proxy | TTL |
|------|------|---------|-------|-----|
| A | `api` | `<VPS_PUBLIC_IP>` | ☁️ Proxied | Auto |
| A | `@` | `<VPS_PUBLIC_IP>` | ☁️ Proxied | Auto |
| CNAME | `www` | `kinrel.app` | ☁️ Proxied | Auto |

> ☁️ **Proxied** (orange cloud) means traffic goes through Cloudflare CDN.

### 3.3 Configure SSL/TLS

Go to **SSL/TLS → Overview**:
- Set mode to **Full (Strict)**

> This means Cloudflare validates the origin cert. Since we use Cloudflare Origin Pull CA, the self-signed cert on the VPS is acceptable.

### 3.4 Enable Cloudflare Origin Pull

1. Go to **SSL/TLS → Origin Server**
2. Click **Create Certificate**
3. Select: **Let Cloudflare generate a private key and CSR**
4. Key type: **RSA (2048)**
5. Hostnames: `*.kinrel.app`, `kinrel.app`
6. Click **Create**
7. Copy the **Origin Certificate** to `/opt/kinrel/nginx/ssl/cert.pem`
8. Copy the **Private Key** to `/opt/kinrel/nginx/ssl/key.pem`

```bash
# On the VPS, replace the self-signed certs with Cloudflare-generated ones
sudo nano /opt/kinrel/nginx/ssl/cert.pem   # Paste Origin Certificate
sudo nano /opt/kinrel/nginx/ssl/key.pem     # Paste Private Key
sudo chmod 600 /opt/kinrel/nginx/ssl/key.pem
```

### 3.5 Additional Cloudflare Settings

| Setting | Location | Value |
|---------|----------|-------|
| Always Use HTTPS | SSL/TLS → Edge Certificates | ✅ ON |
| Minimum TLS Version | SSL/TLS → Edge Certificates | TLS 1.2 |
| Auto Minify | Speed → Optimization | ✅ All |
| Brotli | Speed → Optimization | ✅ ON |
| Rocket Loader | Speed → Optimization | ❌ OFF (can break WebSocket) |
| Security Level | Security → Settings | Medium |

### 3.6 Configure WebSocket Support

Cloudflare supports WebSocket by default on all plans. No special configuration needed — just ensure:

1. **Rocket Loader** is OFF (it can interfere with Socket.IO)
2. **SSL mode** is Full (Strict)
3. The Nginx config already handles the `/socket.io/` upgrade path

---

## Step 4: Configure Supabase

Your Supabase project is already set up at `promxswvsnvilplmrtsj`. Verify these settings:

### 4.1 Database

1. Go to **Database → Connection string**
2. Copy the **pooled** connection string (port 6543) → `DATABASE_URL`
3. Copy the **direct** connection string (port 5432) → `DIRECT_URL`

### 4.2 Authentication

1. Go to **Authentication → URL Configuration**
2. Add your site URL: `https://kinrel.app`
3. Add redirect URLs:
   - `https://kinrel.app/**`
   - `capabile://**`
   - `com.daxelo.kinrel://**`

### 4.3 Run Prisma Migrations

```bash
# On the VPS
cd /opt/kinrel/repo/server

# Set the environment
export DATABASE_URL="postgresql://postgres.promxswvsnvilplmrtsj:[PASSWORD]@aws-0-[region].pooler.supabase.com:6543/postgres"
export DIRECT_URL="postgresql://postgres.promxswvsnvilplmrtsj:[PASSWORD]@aws-0-[region].pooler.supabase.com:5432/postgres"

# Generate Prisma client
npx prisma generate

# Run migrations
npx prisma migrate deploy
```

### 4.4 Row Level Security (RLS)

The project includes RLS policies in `server/prisma/rls-policies.sql`. To apply:

1. Go to **SQL Editor** in Supabase Dashboard
2. Paste the contents of `rls-policies.sql`
3. Click **Run**

---

## Step 5: Deploy the Stack

### 5.1 First Deployment

```bash
# On the VPS
cd /opt/kinrel/repo

# Run the deployment script with build flag (first time only)
sudo bash deploy/scripts/deploy.sh --build
```

### 5.2 Verify Deployment

```bash
# Check service status
docker compose -f deploy/docker-compose.prod.yml ps

# Check API health
curl http://localhost/api/health

# Expected response:
# {"status":"ok","db":"connected","uptime":...}

# Check logs
docker compose -f deploy/docker-compose.prod.yml logs -f api
```

### 5.3 Enable Auto-Start on Boot

```bash
# Install the systemd service
sudo cp /opt/kinrel/repo/deploy/systemd/kinrel.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable kinrel

# Verify
sudo systemctl status kinrel
```

---

## Step 6: Update Flutter App API URL

Your Flutter app currently points to Render. Update it to use Cloudflare:

### Option A: Change in Supabase (Recommended — No code change)

If your Flutter app reads the API URL from Supabase or a remote config:

1. Go to Firebase Remote Config or Supabase table
2. Update `API_BASE_URL` to `https://api.kinrel.app`

### Option B: Update codemagic.yaml

In `Daxelo-Kinrel-App/codemagic.yaml`, change:

```yaml
# Before
API_BASE_URL=https://daxelo-kinrel-server.onrender.com

# After  
API_BASE_URL=https://api.kinrel.app
```

### Option C: Use .env file

Create `Daxelo-Kinrel-App/.env`:

```
API_BASE_URL=https://api.kinrel.app
```

### Important: CORS Origins

Make sure `CORS_ORIGINS` in `.env.production` includes all origins that the Flutter app might send requests from.

---

## Step 7: CI/CD — GitHub Actions Deployment

### 7.1 Add GitHub Secrets

Go to your GitHub repo → Settings → Secrets and variables → Actions:

| Secret Name | Value |
|-------------|-------|
| `VPS_HOST` | Your VPS public IP |
| `VPS_USER` | `ubuntu` (or your SSH user) |
| `VPS_SSH_KEY` | Your SSH private key |

### 7.2 Deploy on Push

The workflow at `.github/workflows/deploy-vps.yml` automatically deploys when:
- Code is pushed to `main` branch
- Changes affect `server/` or `deploy/` directories

### 7.3 Manual Deploy

Go to **Actions** tab → **Deploy to Oracle Cloud VPS** → **Run workflow**:
- Toggle `force_rebuild` to `true` if you need to rebuild Docker images

---

## Architecture Deep-Dive

### How Flutter Auth Works (No Changes Needed)

```
1. Flutter App → Supabase Auth (direct HTTPS)
   ├── signUp(email, password) → Supabase creates user
   ├── signIn(email, password) → Supabase returns JWT
   └── JWT stored in Supabase Flutter SDK

2. Flutter App → NestJS API (via Dio HTTP client)
   ├── Every request includes: Authorization: Bearer <Supabase-JWT>
   ├── NestJS JwtStrategy verifies Supabase JWT using SUPABASE_JWT_SECRET
   ├── If user not in local DB, auto-creates from Supabase claims
   └── All subsequent requests authenticated via the same JWT

3. Flutter App → WebSocket (via Socket.IO)
   ├── Connects to wss://api.kinrel.app/socket.io/
   ├── Auth: sends Supabase JWT in handshake
   └── NestJS Gateway validates JWT before allowing room joins
```

### How Cloudflare SSL Works

```
Flutter App / Browser
    │
    │  HTTPS (TLS 1.3)
    ▼
Cloudflare Edge
    │
    │  Validates client request
    │  DDoS protection
    │  Rate limiting
    │  Caching (static assets)
    │
    │  HTTPS (Full Strict mode)
    │  Cloudflare presents Origin Pull client cert
    ▼
Nginx on VPS
    │
    │  Verifies Cloudflare Origin Pull CA
    │  Terminates SSL
    │
    │  HTTP (plain)
    ▼
NestJS API (Docker container)
```

### How Database Works (No Changes Needed)

```
NestJS API (Docker)
    │
    │  Prisma Client
    │  DATABASE_URL (pooled, port 6543 via PgBouncer)
    ▼
Supabase PostgreSQL
    │
    ├── Prisma Migrations (via DIRECT_URL, port 5432)
    ├── Row Level Security (RLS) policies
    └── Automatic backups
```

---

## Monitoring & Maintenance

### Daily Checks

```bash
# Quick health check
curl -s https://api.kinrel.app/api/health | jq .

# Service status
docker compose -f /opt/kinrel/repo/deploy/docker-compose.prod.yml ps
```

### View Logs

```bash
# API logs (live)
docker compose -f /opt/kinrel/repo/deploy/docker-compose.prod.yml logs -f api

# Nginx access logs
docker compose -f /opt/kinrel/repo/deploy/docker-compose.prod.yml exec nginx tail -f /var/log/nginx/access.log

# Redis status
docker compose -f /opt/kinrel/repo/deploy/docker-compose.prod.yml exec redis redis-cli info
```

### Backup

```bash
# Quick backup
sudo bash /opt/kinrel/repo/deploy/scripts/backup.sh

# Full backup (includes Redis)
sudo bash /opt/kinrel/repo/deploy/scripts/backup.sh --full
```

### Restart Services

```bash
# Restart API only
docker compose -f /opt/kinrel/repo/deploy/docker-compose.prod.yml restart api

# Restart everything
docker compose -f /opt/kinrel/repo/deploy/docker-compose.prod.yml restart

# Full rebuild
docker compose -f /opt/kinrel/repo/deploy/docker-compose.prod.yml down
docker compose -f /opt/kinrel/repo/deploy/docker-compose.prod.yml --env-file /opt/kinrel/.env.production up -d --build
```

### SSL Certificate Renewal

Self-signed certs expire in 10 years. Cloudflare Origin Certs expire in 15 years. No auto-renewal needed, but check:

```bash
sudo bash /opt/kinrel/repo/deploy/scripts/ssl.sh
```

---

## Troubleshooting

### API Not Responding

```bash
# Check if containers are running
docker ps

# Check API logs
docker logs kinrel-api --tail 100

# Check if port 3001 is listening
curl http://localhost:3001/api/health

# Check Nginx
docker logs kinrel-nginx --tail 100
```

### WebSocket Not Working

1. Ensure Cloudflare **Rocket Loader** is OFF
2. Check Nginx is passing `/socket.io/` with upgrade headers
3. Test: `wscat -c wss://api.kinrel.app/socket.io/?EIO=4&transport=websocket`

### Cloudflare 502 Bad Gateway

1. Verify Nginx is running: `docker ps | grep nginx`
2. Verify API is healthy: `docker ps | grep kinrel-api`
3. Check SSL certs: `ls -la /opt/kinrel/nginx/ssl/`
4. Ensure SSL mode is **Full (Strict)** in Cloudflare

### Oracle Cloud Firewall Issues

Oracle Cloud has TWO firewalls: **Security List** (VCN level) and **iptables** (OS level).

```bash
# Check iptables
sudo iptables -L -n

# If ports are blocked at OS level:
sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 443 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 22 -j ACCEPT

# Persist iptables rules
sudo netfilter-persistent save
```

### Memory Issues (1GB RAM VPS)

```bash
# Check memory usage
free -h

# Check swap
swapon --show

# If no swap, add it:
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

---

## File Structure

```
deploy/
├── docker-compose.prod.yml       # Production Docker Compose config
├── .env.production.template      # Environment variables template
├── nginx/
│   ├── nginx.conf                # Nginx reverse proxy config
│   └── conf.d/                   # Additional Nginx configs (empty)
├── scripts/
│   ├── setup-vps.sh              # Initial VPS setup (run once)
│   ├── deploy.sh                 # Deploy/update the stack
│   ├── backup.sh                 # Database & config backup
│   └── ssl.sh                    # SSL certificate management
├── systemd/
│   └── kinrel.service            # Auto-start on boot
└── DEPLOYMENT.md                 # This guide
```

---

## Cost Summary

| Service | Tier | Monthly Cost |
|---------|------|-------------|
| Oracle Cloud VM | Always Free | **$0** |
| Cloudflare | Free | **$0** |
| Supabase | Free (500MB DB, 1GB storage) | **$0** |
| GitHub Actions | Free (2,000 min/month) | **$0** |
| **Total** | | **$0/month** |

> 💡 Supabase Free tier includes 500MB PostgreSQL, 1GB Storage, 50,000 Auth users — sufficient for initial launch. Upgrade to Pro ($25/month) when needed.

---

## Quick Reference

```bash
# Setup VPS (first time only)
sudo bash /opt/kinrel/repo/deploy/scripts/setup-vps.sh

# Configure environment
nano /opt/kinrel/.env.production

# Deploy
sudo bash /opt/kinrel/repo/deploy/scripts/deploy.sh --build

# Update (after code changes)
sudo bash /opt/kinrel/repo/deploy/scripts/deploy.sh

# Backup
sudo bash /opt/kinrel/repo/deploy/scripts/backup.sh

# Check health
curl https://api.kinrel.app/api/health

# View logs
docker compose -f /opt/kinrel/repo/deploy/docker-compose.prod.yml logs -f api
```
