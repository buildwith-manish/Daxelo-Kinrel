# Task V3P1-a — Backend Security Fix Agent

## Task: V3 Phase 1 — CARRY-04 (login lockout) + CARRY-05 (2FA backup codes)

## Changes Made

### CARRY-04: Per-account login lockout
**File**: `server/src/modules/auth/auth.service.ts`
- Added `MAX_LOGIN_ATTEMPTS = 10` and `LOCKOUT_TTL = 900` class constants
- In `login()`: Lockout check before password verification (Redis `login_lock:${userId}`)
- In `login()`: Failed attempt increment and auto-lock after 10 failures (Redis `login_attempts:${userId}`)
- In `login()`: Attempt counter cleanup on successful login
- All Redis ops guarded with `if (this.redis)` for graceful degradation

### CARRY-05: 2FA Backup Codes
**Files**: `server/src/modules/auth/auth.service.ts`, `server/prisma/schema.prisma`
- Schema: Added `backupCodes String[] @default([])` to User model
- `setup2FA()`: Generates 8 backup codes (8-hex-char uppercase), stores bcrypt hashes, returns plaintext
- `loginVerify2FA()`: TOTP fallback — bcrypt.compare against backup codes, removes used code on match
- `disable2FA()`: Clears backup codes array alongside 2FA fields

## Verification
- TypeScript compilation: 0 errors
- Prisma client regenerated successfully with new backupCodes field
- `prisma db push` not executed (no DATABASE_URL in sandbox) — schema validated via generate + tsc
