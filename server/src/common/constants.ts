/**
 * Named constants for magic numbers across the Daxelo Kinrel backend.
 * All values that were previously hardcoded are centralized here.
 */

// ── Bcrypt ────────────────────────────────────────────────────────────
export const BCRYPT_ROUNDS = 12;

// ── TOTP / 2FA ────────────────────────────────────────────────────────
export const TOTP_WINDOW = 2;

// ── Graph Engine ──────────────────────────────────────────────────────
export const GRAPH_CACHE_TTL_SECONDS = 60;
export const MAX_GRAPH_DEPTH = 50;
export const MAX_GRAPH_NODES = 500;
export const DEFAULT_GRAPH_DEPTH = 10;

// ── Token Cleanup ─────────────────────────────────────────────────────
export const TOKEN_CLEANUP_DAYS = 30;

// ── Families ──────────────────────────────────────────────────────────
export const MAX_CONCURRENT_FAMILIES = 3;

// ── AI Chat Sessions ──────────────────────────────────────────────────
export const SESSION_TTL_SECONDS = 3600; // 1 hour

// ── Redis ─────────────────────────────────────────────────────────────
export const REDIS_MAX_RETRIES = 3;

// ── Auth Throttling ───────────────────────────────────────────────────
export const AUTH_THROTTLE_LIMIT = 5;
export const AUTH_THROTTLE_TTL_MS = 60_000;

// ── Rate Limiting ─────────────────────────────────────────────────────
export const THROTTLE_SHORT_TTL = 1000;
export const THROTTLE_SHORT_LIMIT = 20;
export const THROTTLE_LONG_TTL = 60000;
export const THROTTLE_LONG_LIMIT = 200;

// ── Password Change ───────────────────────────────────────────────────
export const PASSWORD_CHANGE_REVOKE_TTL_SECONDS = 900; // 15 minutes

// ── Challenge Token (2FA) ─────────────────────────────────────────────
export const CHALLENGE_TOKEN_EXPIRY = '5m';

// ── Family Roles ──────────────────────────────────────────────────────
export const ROLE_HIERARCHY: Record<string, number> = {
  viewer: 1,
  member: 2,
  editor: 3,
  admin: 4,
};
