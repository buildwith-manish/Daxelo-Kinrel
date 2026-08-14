# GitHub Actions + Vercel Deployment — Setup Guide

This document explains exactly which secrets to set in GitHub, how the workflows use them, and how to revoke them when you're done.

## ⚠️ Important — Token Hygiene

**Never paste a Vercel (or any cloud) token into a chat, commit message, PR description, or issue.** Once a token touches any of those surfaces, consider it compromised — revoke immediately at https://vercel.com/account/tokens.

The tokens used by these workflows live **only** in GitHub's encrypted secrets store. They are never logged, never echoed, and never visible in the workflow file.

---

## Workflows

### Server (`repos/daxelo-kinrel-server/.github/workflows/`)

| File | Trigger | Purpose |
|------|---------|---------|
| `ci.yml` | push / PR to `main`, `develop` | TypeScript typecheck, 53-test Jest suite, NestJS build, Prisma schema validation |
| `vercel-deploy.yml` | push to `main` (after CI passes), or manual | Build → Deploy to Vercel → Poll Vercel API until READY/ERROR |

### Flutter app (`repos/daxelo-kinrel-app/.github/workflows/`)

| File | Trigger | Purpose |
|------|---------|---------|
| `flutter-ci.yml` | push / PR | `flutter analyze`, drift codegen sync check, `flutter test`, debug APK smoke build |
| `vercel-deploy.yml` | push to `main`, or manual | `flutter build web` → Deploy to Vercel → Poll until READY/ERROR |

---

## Required Repository Secrets

Configure at: `https://github.com/<owner>/<repo>/settings/secrets/actions`

### Server repo

| Secret name | Where to get it | Scope needed |
|-------------|-----------------|--------------|
| `VERCEL_TOKEN` | https://vercel.com/account/tokens → Create Token | `Deploy` only |
| `VERCEL_ORG_ID` | `vercel link` locally → printed to terminal, or Settings → General | — |
| `VERCEL_PROJECT_ID_SERVER` | `.vercel/project.json` after `vercel link`, or project Settings → General | — |

### Flutter app repo

| Secret name | Where to get it | Scope needed |
|-------------|-----------------|--------------|
| `VERCEL_TOKEN` | Same token as server (or a separate one) | `Deploy` only |
| `VERCEL_ORG_ID` | Same as server | — |
| `VERCEL_PROJECT_ID_APP` | `.vercel/project.json` after `vercel link` | — |

### Optional: `DATABASE_URL` for integration tests

The current test suite runs against the local JSON fixture (no DB needed). If you add a Prisma-backed test later, set `DATABASE_URL` as a secret pointing to a throwaway Postgres instance.

---

## How Vercel Build Monitoring Works

The `monitor-build.mjs` script:

1. Receives the deploy URL printed by `vercel deploy`.
2. Calls `GET https://api.vercel.com/v13/deployments?teamId=$ORG_ID&limit=20` to resolve the URL to a deployment ID.
3. Polls `GET https://api.vercel.com/v13/deployments/{id}?teamId=$ORG_ID` every 5 seconds.
4. Prints state transitions to the GitHub Actions log.
5. Exits 0 on `READY`, 1 on `ERROR` / `CANCELED`, 1 on 10-minute timeout.
6. The token is passed via argv, never echoed, never logged.

The script never prints the token. It only prints state transitions like:
```
[0.0s]  state=BUILDING
[5.0s]  state=BUILDING
[42.3s] state=READY
✓ Deployment READY (took 42.3s)
  Inspection: https://vercel.com/team_xxx/daxelo-kinrel-server/dep_xxx
```

### Verifying the Monitor Locally (no token needed)

The script has a `--dry-run` mode that simulates all four Vercel build outcomes without touching the network or requiring any token. Use it to verify CI behavior before pushing:

```bash
node scripts/vercel/monitor-build.mjs --dry-run success    # exits 0
node scripts/vercel/monitor-build.mjs --dry-run error      # exits 1
node scripts/vercel/monitor-build.mjs --dry-run canceled   # exits 1
node scripts/vercel/monitor-build.mjs --dry-run timeout    # exits 1 (after 2s)
```

The dry-run mode is also covered by the Jest suite (`test/monitor-build.spec.ts` — 7 tests) so any regression in state-handling logic will fail CI.

---

## Running the Workflows Manually

Both `vercel-deploy.yml` files accept `workflow_dispatch` so you can trigger them from the Actions tab:

1. Go to `https://github.com/<owner>/<repo>/actions/workflows/vercel-deploy.yml`
2. Click "Run workflow"
3. Pick the branch (usually `main`)
4. Watch the live log — the monitor script prints state every 5s.

---

## Revoking Tokens

When you're done with deployments (or if you suspect a leak):

1. Go to https://vercel.com/account/tokens
2. Find the token you created for this project.
3. Click "Delete".
4. (Optional) Remove the secret from GitHub: `https://github.com/<owner>/<repo>/settings/secrets/actions` → click the trash icon next to `VERCEL_TOKEN`.
5. Future deploys will fail with `Vercel API error: 403` — that's the signal the token is properly revoked.

---

## What the Workflows Do NOT Do

By design, these workflows:

- ❌ Do NOT auto-create Vercel projects. You must `vercel link` once locally.
- ❌ Do NOT manage DNS or custom domains.
- ❌ Do NOT run database migrations on deploy (Prisma migrations are run separately via `prisma migrate deploy` — typically in a release script, not in CI).
- ❌ Do NOT expose any token in logs or commit comments. The deploy URL is posted as a commit comment, but never the token.

If you need any of those, say the word and I'll extend the workflows.
