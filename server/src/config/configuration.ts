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
 */

const REQUIRED_VARS = [
  'JWT_ACCESS_SECRET',
  'JWT_REFRESH_SECRET',
  'DATABASE_URL',
  'SUPABASE_URL',
  'SUPABASE_SERVICE_ROLE_KEY',
  'GOOGLE_AI_API_KEY',
  'ENCRYPTION_KEY',
];

export function validate(config: Record<string, unknown>) {
  const strictMode = config.STRICT_CONFIG === 'true';
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

  // Return all config values as-is (with defaults for missing vars)
  return {
    ...config,
    DATABASE_URL: config.DATABASE_URL || 'postgresql://placeholder:placeholder@localhost:5432/placeholder',
    REDIS_URL: config.REDIS_URL || 'redis://localhost:6379',
    PORT: config.PORT || 3000,
    API_PREFIX: config.API_PREFIX || 'api',
    NODE_ENV: config.NODE_ENV || 'development',
  } as Record<string, unknown>;
}
