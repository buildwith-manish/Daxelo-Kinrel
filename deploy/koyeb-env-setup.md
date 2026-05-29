# Koyeb Environment Variables — Quick Reference

> Configure these in **Koyeb Dashboard → Service → Environment Variables**.
> Mark secrets by clicking the **lock icon** to encrypt them at rest.
> Koyeb automatically restarts the service when environment variables change.

---

## Koyeb-Specific Notes

1. **No `.env` file support** — Koyeb uses environment variables injected at runtime. All configuration must be set through the web dashboard or CLI.

2. **Variable changes trigger redeploy** — When you add, modify, or remove an environment variable, Koyeb automatically redeploys the service with the new values.

3. **Secret encryption** — Variables marked as secrets (lock icon) are encrypted at rest and masked in logs. Always mark passwords, API keys, and tokens as secrets.

4. **No Redis on free tier** — The free tier supports only 1 service. Leave `REDIS_URL` empty — the app falls back to in-memory caching. See the Redis section below for external alternatives.

5. **Firebase Private Key** — When pasting `FIREBASE_PRIVATE_KEY`, preserve the `\n` characters as literal `\n` (not actual newlines). Koyeb's env var editor handles this correctly.

6. **Bulk import** — Koyeb supports adding multiple variables at once. Click "Bulk Import" and paste `KEY=VALUE` pairs (one per line).

---

## 1. Server Config

| Variable | Value | Secret? | Notes |
|----------|-------|---------|-------|
| `NODE_ENV` | `production` | No | Required. Enables production optimizations. Pre-configured in `.koyeb/config.yaml`. |
| `PORT` | `3001` | No | **Required.** Must be `3001` — matches the Koyeb service port and Dockerfile EXPOSE. Pre-configured in `.koyeb/config.yaml`. |
| `API_PREFIX` | `api` | No | All routes become `/api/*`. Pre-configured in `.koyeb/config.yaml`. |
| `FRONTEND_URL` | `https://kinrel.app` | No | Used for CORS and redirect URLs. Pre-configured in `.koyeb/config.yaml`. |

---

## 2. Database (Supabase PostgreSQL)

| Variable | Value | Secret? | Where to Find |
|----------|-------|---------|---------------|
| `DATABASE_URL` | `postgresql://postgres.REF:PASS@aws-0-REGION.pooler.supabase.com:6543/postgres` | Yes | Supabase Dashboard → Settings → Database → Connection string → **Pooled** (port 6543) |
| `DIRECT_URL` | `postgresql://postgres:PASS@db.REF.supabase.co:5432/postgres` | Yes | Supabase Dashboard → Settings → Database → Connection string → **Direct** (port 5432) |

> **IMPORTANT:** `DATABASE_URL` uses the **pooled** connection (Supavisor, port 6543) for runtime queries. This is critical on Koyeb's nano instance where connection pooling reduces memory overhead.
>
> `DIRECT_URL` uses the **direct** connection (port 5432) for Prisma migrations only. Run migrations locally or via the Koyeb Console.

### How to get these values:

1. Go to [Supabase Dashboard](https://supabase.com/dashboard)
2. Select your project (`promxswvsnvilplmrtsj`)
3. Click **Settings** (gear icon) → **Database**
4. Scroll to **Connection string** section
5. Switch between **Pooled** and **Direct** tabs
6. Copy the URI and replace `[YOUR-PASSWORD]` with your database password

---

## 3. Authentication (JWT)

| Variable | Value | Secret? | How to Generate |
|----------|-------|---------|-----------------|
| `JWT_ACCESS_SECRET` | *(64-char hex string)* | Yes | `openssl rand -hex 32` |
| `JWT_ACCESS_EXPIRATION` | `15m` | No | Access token lifetime. Pre-configured in `.koyeb/config.yaml`. |
| `JWT_REFRESH_SECRET` | *(64-char hex string)* | Yes | `openssl rand -hex 32` |
| `JWT_REFRESH_EXPIRATION` | `7d` | No | Refresh token lifetime. Pre-configured in `.koyeb/config.yaml`. |

> Generate secrets on your local machine:
> ```bash
> openssl rand -hex 32
> ```
> Run it twice — once for access, once for refresh. Each produces a 64-character hex string.
>
> **Koyeb tip:** Mark both JWT secrets with the lock icon so they're encrypted at rest.

---

## 4. OAuth (Google)

| Variable | Value | Secret? | Where to Find |
|----------|-------|---------|---------------|
| `GOOGLE_CLIENT_ID` | *(from Google Cloud)* | No | Google Cloud Console → APIs & Services → Credentials → OAuth 2.0 Client IDs |
| `GOOGLE_CLIENT_SECRET` | *(from Google Cloud)* | Yes | Same location → Click client → Copy secret |
| `GOOGLE_CALLBACK_URL` | `https://api.kinrel.app/api/auth/google/callback` | No | Must match the authorized redirect URI in Google Cloud Console exactly. |

> Leave empty if Google OAuth is not yet configured. The app runs fine without it.

> **Koyeb note:** Update the Google Cloud Console redirect URL to use your Koyeb domain (e.g., `https://kinrel-api-abc123.koyeb.app/api/auth/google/callback`) during initial testing, then switch to the custom domain after DNS is configured.

---

## 5. Supabase (Auth + Storage + Realtime)

| Variable | Value | Secret? | Where to Find |
|----------|-------|---------|---------------|
| `SUPABASE_URL` | `https://promxswvsnvilplmrtsj.supabase.co` | No | Supabase Dashboard → Settings → API → Project URL |
| `SUPABASE_ANON_KEY` | `eyJhb...` | No | Supabase Dashboard → Settings → API → anon public |
| `SUPABASE_JWT_SECRET` | *(long string)* | Yes | Supabase Dashboard → Settings → API → JWT Secret |
| `SUPABASE_SERVICE_ROLE_KEY` | `eyJhb...` | Yes | Supabase Dashboard → Settings → API → service_role (bypasses RLS) |

### How to find Supabase keys:

1. Go to [Supabase Dashboard](https://supabase.com/dashboard)
2. Select your project
3. Click **Settings** (gear icon) → **API**
4. Copy each value from the corresponding field:
   - **Project URL** → `SUPABASE_URL`
   - **anon public** → `SUPABASE_ANON_KEY`
   - **JWT Secret** → `SUPABASE_JWT_SECRET` (click "Reveal" if hidden)
   - **service_role** → `SUPABASE_SERVICE_ROLE_KEY` (click "Reveal")

> **Koyeb tip:** Mark `SUPABASE_JWT_SECRET` and `SUPABASE_SERVICE_ROLE_KEY` as secrets (lock icon). The anon key is safe to leave unencrypted — it's designed to be public.

---

## 6. AI Features

| Variable | Value | Secret? | Where to Find |
|----------|-------|---------|---------------|
| `Z_AI_API_KEY` | *(API key)* | Yes | Provided by the z-ai-web-dev-sdk team / dashboard |

> Leave empty if AI features are not yet enabled. AI Chat, AI Voice, AI Cards, and Content Moderation will gracefully disable.
>
> **Koyeb nano note:** AI features that make external API calls may increase response latency on the nano instance. Monitor response times and consider upgrading to micro if AI features are heavily used.

---

## 7. Media Storage (Cloudinary)

| Variable | Value | Secret? | Where to Find |
|----------|-------|---------|---------------|
| `CLOUDINARY_CLOUD_NAME` | *(cloud name)* | No | Cloudinary Dashboard → Account Details → Cloud Name |
| `CLOUDINARY_API_KEY` | *(API key)* | No | Cloudinary Dashboard → Account Details → API Key |
| `CLOUDINARY_API_SECRET` | *(API secret)* | Yes | Cloudinary Dashboard → Account Details → API Secret |

> Leave empty if using Supabase Storage instead. Photo upload features will be limited.

---

## 8. Email (SMTP)

| Variable | Value | Secret? | Where to Find |
|----------|-------|---------|---------------|
| `SMTP_HOST` | `smtp.gmail.com` | No | Your email provider's SMTP hostname |
| `SMTP_PORT` | `587` | No | TLS port for SMTP |
| `SMTP_USER` | `your@gmail.com` | No | Your email address |
| `SMTP_PASS` | *(app password)* | Yes | Google Account → Security → App passwords (NOT your Gmail password) |

### How to generate a Gmail App Password:

1. Go to [Google Account → Security](https://myaccount.google.com/security)
2. Ensure 2-Step Verification is enabled
3. Search for **"App passwords"** in the security settings
4. Create a new app password (select "Mail" + your device)
5. Copy the 16-character password → paste as `SMTP_PASS`

---

## 9. Payments

| Variable | Value | Secret? | Where to Find |
|----------|-------|---------|---------------|
| `RAZORPAY_KEY_ID` | `rzp_live_...` | No | Razorpay Dashboard → Settings → API Keys |
| `RAZORPAY_KEY_SECRET` | *(secret)* | Yes | Same location — shown once when created |
| `STRIPE_SECRET_KEY` | `sk_live_...` | Yes | Stripe Dashboard → Developers → API keys → Secret key |
| `STRIPE_WEBHOOK_SECRET` | `whsec_...` | Yes | Stripe Dashboard → Developers → Webhooks → Signing secret |

> Leave empty if payment integration is not yet configured.
>
> **Koyeb note for webhooks:** Update the Stripe webhook endpoint URL to `https://api.kinrel.app/api/payments/webhook/stripe` after your custom domain is configured.

---

## 10. CORS & Redis

| Variable | Value | Secret? | Notes |
|----------|-------|---------|-------|
| `CORS_ORIGINS` | `https://kinrel.app,https://www.kinrel.app,capabile://,com.daxelo.kinrel` | No | Comma-separated. Pre-configured in `.koyeb/config.yaml`. |
| `REDIS_URL` | *(empty or external)* | No | See Redis section below. |

### Redis on Koyeb

The free tier only supports 1 service — you cannot deploy Redis alongside the API. Options:

| Option | `REDIS_URL` Value | Cost |
|--------|-------------------|------|
| **No Redis (recommended for start)** | Leave empty | $0 |
| **Upstash Redis** (free tier) | `rediss://default:PASSWORD@upstash-redis.cloud.redislabs.com:6379` | $0 |
| **Redis Cloud** (free tier) | `redis://default:PASSWORD@redis-xxxxx.c1.us-east-1.ec2.cloud.redislabs.com:6379` | $0 |

> **Without Redis**, the app uses in-memory caching. This works fine for single-instance deployments (which is what the free tier provides). If you scale to multiple instances later, you'll need an external Redis to share cache across instances.
>
> **Upstash tip:** Use the `rediss://` protocol (with double 's') for TLS-encrypted connections, which Koyeb requires for external services.

---

## 11. Monitoring

| Variable | Value | Secret? | Where to Find |
|----------|-------|---------|---------------|
| `SENTRY_DSN` | `https://xxx@sentry.io/yyy` | No | Sentry Dashboard → Project → Settings → Client Keys → DSN |
| `BETTERSTACK_SOURCE_TOKEN` | *(token)* | Yes | BetterStack → Sources → Add source → Copy token |

> Leave empty if monitoring is not yet configured.
>
> **Koyeb tip:** Koyeb provides built-in metrics (CPU, memory, request count, response time) in the dashboard. Sentry/BetterStack add application-level error tracking and log aggregation on top of that.

---

## 12. Firebase (Push Notifications)

| Variable | Value | Secret? | Where to Find |
|----------|-------|---------|---------------|
| `FIREBASE_PROJECT_ID` | `your-project-id` | No | Firebase Console → Project Settings → General |
| `FIREBASE_CLIENT_EMAIL` | `firebase-adminsdk-xxxx@project.iam.gservice.com` | No | Firebase Console → Project Settings → Service Accounts → Generate new private key → extract `client_email` |
| `FIREBASE_PRIVATE_KEY` | `-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n` | Yes | Same JSON file → extract `private_key`. **Must preserve `\n` characters.** |

> **CRITICAL for Koyeb:** When pasting `FIREBASE_PRIVATE_KEY` into Koyeb's environment variable editor, the `\n` characters must be preserved as literal `\n` (not as actual newlines). Paste it exactly as it appears in the JSON file from Firebase. Koyeb's editor handles this correctly.

---

## 13. Logging & Alerting

| Variable | Value | Secret? | Notes |
|----------|-------|---------|-------|
| `LOG_LEVEL` | `info` | No | Options: `debug`, `info`, `warn`, `error`. Pre-configured in `.koyeb/config.yaml`. |
| `LOG_DIR` | `/app/logs` | No | Directory inside the container for log files. |
| `ERROR_RATE_ALERT_THRESHOLD` | `0.01` | No | Alert when error rate exceeds 1%. Pre-configured in `.koyeb/config.yaml`. |
| `P99_ALERT_THRESHOLD_MS` | `2000` | No | Alert when P99 latency exceeds 2 seconds. Pre-configured in `.koyeb/config.yaml`. |

> **Koyeb note on LOG_DIR:** The Koyeb container filesystem is ephemeral — log files written to `/app/logs` are lost on redeploy. For persistent logs, configure BetterStack (Section 11) or view real-time logs in the Koyeb dashboard (Service → Logs).

---

## Quick Setup Checklist

Copy this checklist and tick off each section as you configure it:

- [ ] **Section 1** — Server Config (4 vars, pre-configured in `.koyeb/config.yaml`)
- [ ] **Section 2** — Database (2 vars)
- [ ] **Section 3** — JWT Auth (4 vars, 2 pre-configured in `.koyeb/config.yaml`)
- [ ] **Section 4** — Google OAuth (3 vars, optional)
- [ ] **Section 5** — Supabase (4 vars)
- [ ] **Section 6** — AI Features (1 var, optional)
- [ ] **Section 7** — Cloudinary (3 vars, optional)
- [ ] **Section 8** — SMTP Email (4 vars, optional)
- [ ] **Section 9** — Payments (4 vars, optional)
- [ ] **Section 10** — CORS & Redis (2 vars, CORS pre-configured)
- [ ] **Section 11** — Monitoring (2 vars, optional)
- [ ] **Section 12** — Firebase (3 vars, optional)
- [ ] **Section 13** — Logging (4 vars, pre-configured in `.koyeb/config.yaml`)

**Minimum required for first deploy:** Sections 1, 2, 3, 5, 10 (15 variables total).
Everything else can be added incrementally — the app gracefully degrades when optional services are not configured.

---

## Bulk Import Template

Copy the following block into Koyeb's "Bulk Import" field, replacing placeholder values:

```env
# ── Section 1: Server Config (pre-configured in .koyeb/config.yaml) ──
# NODE_ENV=production
# PORT=3001
# API_PREFIX=api
# FRONTEND_URL=https://kinrel.app

# ── Section 2: Database (REQUIRED) ──
DATABASE_URL=postgresql://postgres.REF:REPLACE_PASSWORD@aws-0-REGION.pooler.supabase.com:6543/postgres
DIRECT_URL=postgresql://postgres:REPLACE_PASSWORD@db.REF.supabase.co:5432/postgres

# ── Section 3: JWT Auth (REQUIRED — generate secrets) ──
# JWT_ACCESS_EXPIRATION=15m
# JWT_REFRESH_EXPIRATION=7d
JWT_ACCESS_SECRET=REPLACE_WITH_openssl_rand_hex_32
JWT_REFRESH_SECRET=REPLACE_WITH_openssl_rand_hex_32

# ── Section 5: Supabase (REQUIRED) ──
SUPABASE_URL=https://promxswvsnvilplmrtsj.supabase.co
SUPABASE_ANON_KEY=REPLACE_WITH_YOUR_ANON_KEY
SUPABASE_JWT_SECRET=REPLACE_WITH_YOUR_JWT_SECRET
SUPABASE_SERVICE_ROLE_KEY=REPLACE_WITH_YOUR_SERVICE_ROLE_KEY

# ── Section 10: CORS (pre-configured in .koyeb/config.yaml) ──
# CORS_ORIGINS=https://kinrel.app,https://www.kinrel.app,capabile://,com.daxelo.kinrel
# REDIS_URL=
```

> **Lines starting with `#` are comments** — Koyeb will ignore them during bulk import. Uncomment (remove `#`) any line you want to import. Variables already in `.koyeb/config.yaml` are commented out since they're pre-configured.

---

## Koyeb UI Tips

1. **Secret encryption:** Click the lock icon next to a variable to encrypt it. Encrypted values are never visible in the UI after saving — you can only replace them.

2. **Environment variable priority:** Variables set in the Koyeb dashboard override values from `.koyeb/config.yaml`. Use the config file for defaults, and the dashboard for environment-specific overrides.

3. **Redeploy after changes:** Koyeb automatically triggers a redeploy when you modify environment variables. Plan for a ~1-2 minute downtime during the rolling deploy.

4. **Variable references:** You can reference other variables with `${VAR_NAME}` syntax in Koyeb. For example:
   ```
   GOOGLE_CALLBACK_URL=https://${FRONTEND_URL}/api/auth/google/callback
   ```
   However, this only works for variables defined in the same scope.

5. **Debugging env vars:** Use the Koyeb Console (Service → Console) to verify environment variables at runtime:
   ```bash
   echo $NODE_ENV
   echo $DATABASE_URL
   ```
   Secret values are still accessible in the Console but masked in the dashboard.
