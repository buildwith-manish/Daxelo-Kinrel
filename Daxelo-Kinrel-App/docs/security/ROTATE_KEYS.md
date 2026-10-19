# Rotate Keys — Security Action Required

**Date:** 2026-10-20
**Phase:** 1 (Security)
**Status:** ⚠️ ACTION REQUIRED BY THE OWNER

## Summary

Three scripts in this repository contained **hardcoded secrets** that
were committed to git history:

1. `scripts/e2e-test.js` — Supabase `service_role` JWT
2. `scripts/e2e-verify.js` — Supabase `service_role` JWT + DB connection string with password
3. `scripts/setup_turso_table.py` — Turso auth token

The hardcoded values have been **removed from the working tree** (Phase 1
commit `perf(phase1): ...`) and replaced with `process.env` / `os.environ`
reads that throw a clear error if the env var is missing. The variable
names (no values) have been added to `.env.example`.

**However, the old values are STILL in the git history.** Anyone with
read access to this repo can `git log -p` and find them. You must
complete the steps below to fully remediate.

## What I (the automation) could NOT do

- **I cannot rotate the keys for you.** Rotating requires dashboard
  access to Supabase, Turso, and Google Cloud — only you have the
  credentials.
- **I cannot purge git history.** Rewriting history with `git filter-repo`
  or BFG requires force-pushing to the remote, which is a destructive
  operation that must be coordinated with all collaborators. Only the
  repo owner should do this.
- **I cannot verify the old keys are actually revoked.** Only the
  dashboards can confirm this.

## Steps the owner MUST complete

### Step 1: Rotate the Supabase service_role key

1. Go to **Supabase Dashboard** → your project (`promxswvsnvilplmrtsj`)
   → **Settings** → **API**.
2. Under **API Keys**, find the **service_role** key.
3. Click **Rotate** (or **Regenerate**). This creates a new key and
   **immediately invalidates the old one**.
4. Copy the new key. Store it in a secure location (password manager
   or secret manager — NOT in the repo).
5. Update the environment variables in:
   - **Vercel** (Flutter web app) → Settings → Environment Variables →
     add `SUPABASE_SERVICE_ROLE_KEY` = new key (for any server-side
     scripts that run in CI/preview).
   - **GitHub Actions** → Settings → Secrets and variables → Actions →
     add `SUPABASE_SERVICE_ROLE_KEY` = new key (for e2e tests).
   - **Render** (NestJS backend) → if the backend uses the service_role
     key, update its env var too.

### Step 2: Rotate the Turso auth token

1. Go to **Turso Dashboard** → your database
   (`kinrel-kinship-daxelo-kinrel`) → **Settings**.
2. Revoke the existing token and create a new one.
3. Update the `TURSO_AUTH_TOKEN` environment variable wherever the
   `setup_turso_table.py` script runs.

### Step 3: Rotate the Supabase database password

The DB connection string in `scripts/e2e-verify.js` contained a
hardcoded password (`tvAFZQp89nUulXeE`). Rotate it:

1. Go to **Supabase Dashboard** → **Settings** → **Database**.
2. Click **Reset database password**.
3. Copy the new password. Construct the new connection string:
   ```
   postgresql://postgres.promxswvsnvilplmrtsj:<NEW_PASSWORD>@aws-1-ap-southeast-1.pooler.supabase.com:6543/postgres
   ```
4. Set `DATABASE_URL` in your environment (GitHub Actions secret,
   Vercel env var, etc.).

### Step 4: Purge the old secrets from git history

> ⚠️ **WARNING:** This rewrites git history. All collaborators must
> re-clone after this. Force-push is required. **Do this during a
> low-traffic window.**

**Option A: git filter-repo (recommended)**

```bash
# Install git-filter-repo (one-time)
pip install git-filter-repo

# Clone a fresh copy
git clone https://github.com/buildwith-manish/Daxelo-Kinrel.git
cd Daxelo-Kinrel

# Replace the old JWT in ALL commits
echo 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InByb214c3d2c252aWxwbG1ydHNqIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3OTU5NzE4MCwiZXhwIjoyMDk1MTczMTgwfQ.sgaciYwaTVd3FoGqZEe_cQamSXiAXA9SYdLjf2ICcCE==>REDACTED' > /tmp/replacements.txt
echo 'tvAFZQp89nUulXeE==>REDACTED' >> /tmp/replacements.txt
echo 'eyJhbGciOiJFZERTQSIsInR5cCI6IkpXVCJ9.eyJhIjoicnciLCJpYXQiOjE3ODI1NzgxMjQsImlkIjoiMDE5ZjA5YzItMzAwMS03ZGU1LWE3NTQtMWEwZmZmNjQzODljIiwicmlkIjoiODg2ZjM1MzctOGFlZC00ZjdiLTg4MzctMjRmN2ZhZDFhOTIzIn0.pKftSB12uJCZlKHPTjazhmte6uOKieqSG-1s1aiZj-c3pYI9eP2ddcxNah2fZ80m1sREfQW6lzZDFVVgztR3DA==>REDACTED' >> /tmp/replacements.txt

git filter-repo --replace-text /tmp/replacements.txt

# Force-push (WARNING: rewrites history)
git push origin --force --all
git push origin --force --tags

# Tell all collaborators to re-clone
```

**Option B: BFG Repo-Cleaner**

```bash
# Download bfg.jar from https://rtyley.github.io/bfg-repo-cleaner/
java -jar bfg.jar --replace-text replacements.txt
git reflog expire --expire=now --all
git gc --prune=now --aggressive
git push origin --force --all
```

### Step 5: Restrict Firebase / Google API keys

The Google OAuth client IDs in `.env.example` are **public
identifiers** (not secrets), but the API keys associated with them
should be restricted by Android package name + SHA-1 certificate:

1. Go to **Google Cloud Console** → the project
   (`726935858050` for web, `643588134212` for Android/iOS).
2. **APIs & Services** → **Credentials**.
3. For each **API key** (not OAuth client ID):
   - Click the key → **Application restrictions** → **Android apps**.
   - Add the app's package name (`com.daxelo.kinrel`) + the SHA-1 of
     the signing key (debug + release).
4. For the **Web client ID** (`726935858050-...`): restrict to the
   Supabase OAuth callback URL + your Vercel domain.

### Step 6: Verify

After completing steps 1-5, verify:

1. The old service_role JWT no longer works:
   ```bash
   # This should fail with 401 Unauthorized:
   curl -H "apikey: <OLD_JWT>" https://promxswvsnvilplmrtsj.supabase.co/rest/v1/
   ```
2. The gitleaks CI job passes (no secrets found in history after purge).
3. The e2e tests still pass with the new env vars:
   ```bash
   SUPABASE_SERVICE_ROLE_KEY=<NEW_KEY> DATABASE_URL=<NEW_URL> node scripts/e2e-test.js
   ```

## What was changed in the code (Phase 1)

| File | Change |
|------|--------|
| `scripts/e2e-test.js` | Replaced hardcoded `SUPABASE_SERVICE_KEY` with `process.env.SUPABASE_SERVICE_ROLE_KEY` (throws if missing) |
| `scripts/e2e-verify.js` | Replaced hardcoded JWT + DB connection string with `process.env.SUPABASE_SERVICE_ROLE_KEY` + `process.env.DATABASE_URL` (throws if missing) |
| `scripts/setup_turso_table.py` | Removed hardcoded Turso token fallback — `os.environ.get("TURSO_AUTH_TOKEN")` with no default (exits if missing) |
| `.env.example` | Added `SUPABASE_SERVICE_ROLE_KEY` and `DATABASE_URL` variable names (no values) |
| `.github/workflows/ci.yml` | Added `gitleaks` job (Job 0) that scans for secrets and fails if found |

## Why this matters

The Supabase `service_role` key bypasses Row Level Security (RLS) —
it can read, write, and delete ANY data in your database. If an
attacker finds the old key in git history, they can:
- Read all user data (profiles, family members, health heritage, chat)
- Delete or modify any data
- Impersonate any user
- Access the database directly via the connection string

The Turso token gives access to the kinship matrix database. The DB
password gives direct SQL access.

**Rotating the keys is the only way to make the old values useless.**
Purging git history is the only way to make them undiscoverable.
