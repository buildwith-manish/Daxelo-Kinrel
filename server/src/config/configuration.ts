/**
 * Environment variable validation for NestJS ConfigModule.
 *
 * Strategy:
 * - Logs warnings for missing required vars instead of crashing.
 * - This allows the Docker container to start on Render and pass health checks
 *   even before all secrets (DATABASE_URL, JWT secrets, etc.) are configured.
 * - Individual services that depend on these vars will log their own errors
 *   when they try to use them, making debugging straightforward.
 * - To enable strict validation (crash on missing vars), set STRICT_CONFIG=true.
 * - In production (NODE_ENV=production), STRICT_CONFIG defaults to true.
 */

const REQUIRED_VARS = [
  'JWT_ACCESS_SECRET',
  'JWT_REFRESH_SECRET',
  'DATABASE_URL',
  'SUPABASE_URL',
  'SUPABASE_SERVICE_ROLE_KEY',
  'ENCRYPTION_KEY',
];

const RECOMMENDED_VARS = [
  'REDIS_URL',
  'SUPABASE_JWT_SECRET',
  'SMTP_HOST',
  'SMTP_USER',
  'SMTP_PASS',
  'RAZORPAY_KEY_ID',
  'RAZORPAY_KEY_SECRET',
  // Feature-specific — not required for server to start
  'CLOUDINARY_CLOUD_NAME',
  'CLOUDINARY_API_KEY',
  'CLOUDINARY_API_SECRET',
  'DEEPSEEK_API_KEY',
];

export function validate(config: Record<string, unknown>) {
  const isProduction = config.NODE_ENV === 'production';
  const strictMode = config.STRICT_CONFIG === 'true' || (isProduction && config.STRICT_CONFIG !== 'false');

  // ── Required vars ──────────────────────────────────────────────────
  const missing = REQUIRED_VARS.filter(
    (key) => !config[key] || config[key] === '',
  );

  if (missing.length > 0) {
    const message = `⚠️  Missing required environment variables: ${missing.join(', ')}`;

    if (strictMode) {
      throw new Error(message);
    }

    // Non-fatal warning — allows container to start for health checks
    console.warn(message);
    console.warn(
      'Set STRICT_CONFIG=true to enable strict validation (crash on missing vars).',
    );
  }

  // ── Recommended vars ───────────────────────────────────────────────
  const missingRecommended = RECOMMENDED_VARS.filter(
    (key) => !config[key] || config[key] === '',
  );

  if (missingRecommended.length > 0) {
    console.warn(
      `⚠️  Missing recommended environment variables: ${missingRecommended.join(', ')}. ` +
      'Some features may be degraded.',
    );
  }

  // Return all config values as-is (with defaults for missing vars)
  return {
    ...config,
    REDIS_URL: config.REDIS_URL || '',
    PORT: config.PORT || 3000,
    API_PREFIX: config.API_PREFIX || 'api',
    NODE_ENV: config.NODE_ENV || 'development',
  } as Record<string, unknown>;
}
