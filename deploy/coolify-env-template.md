# Coolify Environment Variables — Quick Reference

> Configure these in **Coolify Web UI → Project → Application → Environment Variables**.
> Mark secrets as **"Is Secret"** (eye icon) to hide them in the UI.

---

## 1. Server Config

| Variable | Value | Secret? | Notes |
|----------|-------|---------|-------|
| `NODE_ENV` | `production` | No | Required. Enables production optimizations. |
| `PORT` | `3001` | No | **Required.** Must be `3001` — Coolify maps this port. |
| `API_PREFIX` | `api` | No | All routes become `/api/*`. |
| `FRONTEND_URL` | `https://kinrel.app` | No | Used for CORS and redirect URLs. |

---

## 2. Database (Supabase PostgreSQL)

| Variable | Value | Secret? | Where to Find |
|----------|-------|---------|---------------|
| `DATABASE_URL` | `postgresql://postgres.REF:PASS@aws-0-REGION.pooler.supabase.com:6543/postgres` | Yes | Supabase Dashboard → Settings → Database → Connection string → **Pooled** (port 6543) |
| `DIRECT_URL` | `postgresql://postgres:PASS@db.REF.supabase.co:5432/postgres` | Yes | Supabase Dashboard → Settings → Database → Connection string → **Direct** (port 5432) |

> **IMPORTANT:** `DATABASE_URL` uses the **pooled** connection (Supavisor, port 6543) for runtime.  
> `DIRECT_URL` uses the **direct** connection (port 5432) for Prisma migrations only.

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
| `JWT_ACCESS_EXPIRATION` | `15m` | No | Access token lifetime. |
| `JWT_REFRESH_SECRET` | *(64-char hex string)* | Yes | `openssl rand -hex 32` |
| `JWT_REFRESH_EXPIRATION` | `7d` | No | Refresh token lifetime. |

> Generate secrets on your local machine or in the Coolify terminal:
> ```bash
> openssl rand -hex 32
> ```
> Run it twice — once for access, once for refresh. Each produces a 64-character hex string.

---

## 4. OAuth (Google)

| Variable | Value | Secret? | Where to Find |
|----------|-------|---------|---------------|
| `GOOGLE_CLIENT_ID` | *(from Google Cloud)* | No | Google Cloud Console → APIs & Services → Credentials → OAuth 2.0 Client IDs |
| `GOOGLE_CLIENT_SECRET` | *(from Google Cloud)* | Yes | Same location → Click client → Copy secret |
| `GOOGLE_CALLBACK_URL` | `https://api.kinrel.app/api/auth/google/callback` | No | Must match the authorized redirect URI in Google Cloud Console exactly. |

> Leave empty if Google OAuth is not yet configured. The app runs fine without it.

---

## 5. Supabase (Auth + Storage + Realtime)

| Variable | Value | Secret? | Where to Find |
|----------|-------|---------|---------------|
| `SUPABASE_URL` | `https://promxswvsnvilplmrtsj.supabase.co` | No | Supabase Dashboard → Settings → API → Project URL |
| `SUPABASE_ANON_KEY` | `eyJhb...` | No | Supabase Dashboard → Settings → API → anon public |
| `SUPABASE_JWT_SECRET` | *(long string)* | Yes | Supabase Dashboard → Settings → API → JWT Secret |
| `SUPABASE_SERVICE_ROLE_KEY` | `eyJhb...` | Yes | Supabase Dashboard → Settings → API → service_role (⚠️ **bypasses RLS**) |

### How to find Supabase keys:

1. Go to [Supabase Dashboard](https://supabase.com/dashboard)
2. Select your project
3. Click **Settings** (gear icon) → **API**
4. Copy each value from the corresponding field:
   - **Project URL** → `SUPABASE_URL`
   - **anon public** → `SUPABASE_ANON_KEY`
   - **JWT Secret** → `SUPABASE_JWT_SECRET` (click "Reveal" if hidden)
   - **service_role** → `SUPABASE_SERVICE_ROLE_KEY` (click "Reveal")

---

## 6. AI Features

| Variable | Value | Secret? | Where to Find |
|----------|-------|---------|---------------|
| `Z_AI_API_KEY` | *(API key)* | Yes | Provided by the z-ai-web-dev-sdk team / dashboard |

> Leave empty if AI features are not yet enabled. AI Chat, AI Voice, AI Cards, and Content Moderation will gracefully disable.

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

---

## 10. CORS & Redis

| Variable | Value | Secret? | Notes |
|----------|-------|---------|-------|
| `CORS_ORIGINS` | `https://kinrel.app,https://www.kinrel.app,capabile://,com.daxelo.kinrel` | No | Comma-separated. Add any domains the Flutter app uses. |
| `REDIS_URL` | `redis://kinrel-redis:6379` | No | Uses Coolify service name. If using Coolify's one-click Redis, the name may differ — check Coolify's service list. |

> **Redis URL note:** In Coolify, if you create a Redis service named `kinrel-redis`, use `redis://kinrel-redis:6379`. If Coolify auto-generates the name (e.g., `redis-abc123`), use that name instead. You can find the internal hostname in Coolify → Redis service → Connection Info.

---

## 11. Monitoring

| Variable | Value | Secret? | Where to Find |
|----------|-------|---------|---------------|
| `SENTRY_DSN` | `https://xxx@sentry.io/yyy` | No | Sentry Dashboard → Project → Settings → Client Keys → DSN |
| `BETTERSTACK_SOURCE_TOKEN` | *(token)* | Yes | BetterStack → Sources → Add source → Copy token |

> Leave empty if monitoring is not yet configured.

---

## 12. Firebase (Push Notifications)

| Variable | Value | Secret? | Where to Find |
|----------|-------|---------|---------------|
| `FIREBASE_PROJECT_ID` | `your-project-id` | No | Firebase Console → Project Settings → General |
| `FIREBASE_CLIENT_EMAIL` | `firebase-adminsdk-xxxx@project.iam.gservice.com` | No | Firebase Console → Project Settings → Service Accounts → Generate new private key → extract `client_email` |
| `FIREBASE_PRIVATE_KEY` | `-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n` | Yes | Same JSON file → extract `private_key`. **Must preserve `\n` characters.** |

> **CRITICAL for Coolify:** When pasting `FIREBASE_PRIVATE_KEY` into Coolify's env var UI, the `\n` characters must be preserved as literal `\n` (not as actual newlines). Paste it exactly as it appears in the JSON file.

---

## 13. Logging & Alerting

| Variable | Value | Secret? | Notes |
|----------|-------|---------|-------|
| `LOG_LEVEL` | `info` | No | Options: `debug`, `info`, `warn`, `error` |
| `LOG_DIR` | `/app/logs` | No | Directory inside the container for log files. |
| `ERROR_RATE_ALERT_THRESHOLD` | `0.01` | No | Alert when error rate exceeds 1%. |
| `P99_ALERT_THRESHOLD_MS` | `2000` | No | Alert when P99 latency exceeds 2 seconds. |

---

## Quick Setup Checklist

Copy this checklist and tick off each section as you configure it:

- [ ] **Section 1** — Server Config (4 vars)
- [ ] **Section 2** — Database (2 vars)
- [ ] **Section 3** — JWT Auth (4 vars)
- [ ] **Section 4** — Google OAuth (3 vars, optional)
- [ ] **Section 5** — Supabase (4 vars)
- [ ] **Section 6** — AI Features (1 var, optional)
- [ ] **Section 7** — Cloudinary (3 vars, optional)
- [ ] **Section 8** — SMTP Email (4 vars, optional)
- [ ] **Section 9** — Payments (4 vars, optional)
- [ ] **Section 10** — CORS & Redis (2 vars)
- [ ] **Section 11** — Monitoring (2 vars, optional)
- [ ] **Section 12** — Firebase (3 vars, optional)
- [ ] **Section 13** — Logging (4 vars)

**Minimum required for first deploy:** Sections 1, 2, 3, 5, 10 (15 variables total).  
Everything else can be added incrementally — the app gracefully degrades when optional services are not configured.

---

## Coolify UI Tips

1. **Bulk import:** Coolify supports pasting multiple env vars in `KEY=VALUE` format (one per line). You can copy from `.env.production` and paste directly.

2. **Secret masking:** Click the eye icon next to a variable to mark it as secret. Secret values are hidden in the UI and logs.

3. **Shared variables:** If you have multiple services (API + Redis helper), you can define shared variables at the project level.

4. **Environment preview:** Coolify shows a diff preview before applying changes — review carefully before confirming.

5. **Variable references:** In Coolify v4+, you can reference other variables with `${VAR_NAME}` syntax for DRY configuration.
