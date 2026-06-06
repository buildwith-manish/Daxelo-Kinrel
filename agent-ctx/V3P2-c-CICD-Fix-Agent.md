# V3P2-c — CI/CD Fix Agent

## Task
V3 Phase 2 — CI/CD fixes (2 items: CI-04, CI-05)

## Work Summary

### CI-04 — Deployment Smoke Test
- **Health endpoint**: Already exists at `server/src/health/health.controller.ts` with `@Public()` decorator, returns `{ status, db, redis, uptime, memory, ts }`. No new endpoint needed.
- **Workflow**: Created `.github/workflows/deploy-health.yml` — post-deploy health check workflow:
  - Triggers on push to main (server/ paths) and manual workflow_dispatch
  - Configurable inputs: health_url, max_retries (default 5), retry_delay (default 30s)
  - Retries curl against `/api/health` endpoint with 10s timeout per attempt
  - Displays JSON response on success; fails job on all retries exhausted
  - Default URL: `https://daxelo-kinrel-server.onrender.com/api/health`

### CI-05 — Conventional Commits (commitlint + husky)
- **commitlint.config.js**: Created at project root with `@commitlint/config-conventional` + custom type-enum: `feat, fix, security, perf, refactor, test, docs, ci, chore, revert`
- **Dependencies**: Installed `@commitlint/cli`, `@commitlint/config-conventional`, `husky` as devDependencies in `server/package.json`
- **Husky setup**: Created `server/.husky/commit-msg` hook with `npx --no -- commitlint --edit $1`
- **Prepare script**: Updated to `"cd .. && husky server/.husky"` for monorepo compatibility (git root is project root)

## Files Modified/Created
| File | Action |
|------|--------|
| `.github/workflows/deploy-health.yml` | Created |
| `commitlint.config.js` | Created |
| `server/.husky/commit-msg` | Created |
| `server/package.json` | Modified (3 devDeps + prepare script) |

## Verification
- TypeScript compilation: 0 errors (`npx tsc --noEmit` passes cleanly)
