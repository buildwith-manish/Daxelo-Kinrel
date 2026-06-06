# V3P3-b — Auth Security Test Agent

## Task
V3 Phase 3 — TEST-02: Auth security tests (TOTP replay, lockout, backup codes)

## Work Summary
Added 22 security-focused test cases to `server/src/modules/auth/auth.service.spec.ts` covering 5 critical scenarios that were previously untested.

## Test Categories Added

### 1. TOTP Replay Protection (4 tests)
- First TOTP use succeeds and marks code as used in Redis (`totp_used:${userId}:${code}`, 60s TTL)
- Replayed TOTP code rejected in `verify2FA` (exists=1 → throws "TOTP code already used")
- Replayed TOTP code rejected in `loginVerify2FA` (same check)
- Code-specific Redis keys ensure different codes don't conflict (first use OK, replay blocked)

### 2. Account Lockout (6 tests)
- 9 failed attempts: NOT locked yet (incr=9 < 10, no lockout setex)
- 10 failed attempts: IS locked (incr=10, setex lock key 900s, del attempt key)
- Locked account rejects login with TTL in message ("Account temporarily locked...10 minutes")
- Successful login clears attempt counter (redis.del called)
- After lockout expires (Redis key gone), login works again
- 10th attempt lockout message includes "15 minutes"

### 3. Counter Reset on Successful Login (3 tests)
- Failed attempt then successful login clears counter (del called)
- 5 failed attempts then successful login resets counter
- After successful login, subsequent failed attempts start from 1 (no lockout set)

### 4. Backup Code Generation (4 tests)
- `setup2FA()` returns exactly 8 backup codes
- Each code is 8 uppercase hex characters (/^[0-9A-F]{8}$/)
- Codes stored hashed in DB (bcrypt $2a$/$2b$ format, not plaintext)
- Returned codes are plaintext (unique, not hash format)

### 5. Backup Code Consumption (5 tests)
- Valid backup code authenticates via `loginVerify2FA` (TOTP fails, bcrypt.compare matches)
- Used backup code cannot be reused (removed from array, second call fails)
- After using one code, 7 remain (update called with length-1 array)
- All 8 backup codes used sequentially (loop with jest.clearAllMocks between iterations)
- Invalid backup code throws UnauthorizedException("Invalid 2FA code")

## Technical Details
- Injected Redis mock via `(service as any).redis = mockRedis` since Redis is private and null by default in tests
- Mock Redis object: `{ exists, setex, get, set, del, incr, expire, ttl }`
- Used `bcrypt.hashSync(code, 4)` (low cost) for backup code test speed
- Used real `authenticator.generateSecret()` + `authenticator.generate()` for TOTP tests
- Used `expect.assertions(N)` for tests with try/catch patterns

## Test Results
- Auth spec: 68/68 passing (46 original + 22 new)
- Full suite: 326/326 passing
- Zero failures
