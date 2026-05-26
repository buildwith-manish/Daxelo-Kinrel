/**
 * KINREL Mirror — Core Configuration System
 * Type-safe environment variable access with validation.
 */

export type NodeEnv = 'development' | 'production' | 'test';

export interface AppConfig {
  nodeEnv: NodeEnv;
  isDev: boolean;
  isProd: boolean;
  isTest: boolean;
  port: number;
  databaseUrl: string;
  nextAuthSecret: string;
  nextAuthUrl: string;
  supabaseUrl: string;
  supabaseAnonKey: string;
  whatsappApiUrl: string;
  whatsappPhoneNumberId: string;
  whatsappAccessToken: string;
  whatsappWebhookVerifyToken: string;
  whatsappAppSecret: string;
  apiVersion: string;
  apiPrefix: string;
  jwtAccessExpiry: string;
  jwtRefreshExpiry: string;
  rateLimitWindowMs: number;
  rateLimitMaxRequests: number;
  maxUploadSizeMb: number;
  corsOrigins: string[];
  logLevel: 'debug' | 'info' | 'warn' | 'error';
}

function getEnv(key: string, fallback?: string): string {
  const value = process.env[key] ?? fallback;
  if (value === undefined) {
    throw new Error(`Missing required environment variable: ${key}`);
  }
  return value;
}

function getOptionalEnv(key: string, fallback: string = ''): string {
  return process.env[key] ?? fallback;
}

export const config: AppConfig = {
  nodeEnv: (getOptionalEnv('NODE_ENV', 'development') as NodeEnv),
  isDev: getOptionalEnv('NODE_ENV', 'development') === 'development',
  isProd: getOptionalEnv('NODE_ENV') === 'production',
  isTest: getOptionalEnv('NODE_ENV') === 'test',
  port: parseInt(getOptionalEnv('PORT', '3000'), 10),
  databaseUrl: getEnv('DATABASE_URL', 'file:./db/custom.db'),
  nextAuthSecret: getOptionalEnv('NEXTAUTH_SECRET', 'kinrel-dev-secret-change-in-production'),
  nextAuthUrl: getOptionalEnv('NEXTAUTH_URL', 'http://localhost:3000'),
  supabaseUrl: getOptionalEnv('SUPABASE_URL', ''),
  supabaseAnonKey: getOptionalEnv('SUPABASE_ANON_KEY', ''),
  whatsappApiUrl: getOptionalEnv('WHATSAPP_API_URL', 'https://graph.facebook.com/v18.0'),
  whatsappPhoneNumberId: getOptionalEnv('WHATSAPP_PHONE_NUMBER_ID', ''),
  whatsappAccessToken: getOptionalEnv('WHATSAPP_ACCESS_TOKEN', ''),
  whatsappWebhookVerifyToken: getOptionalEnv('WHATSAPP_WEBHOOK_VERIFY_TOKEN', ''),
  whatsappAppSecret: getOptionalEnv('WHATSAPP_APP_SECRET', ''),
  apiVersion: '1.0.0',
  apiPrefix: '/api',
  jwtAccessExpiry: '15m',
  jwtRefreshExpiry: '7d',
  rateLimitWindowMs: 60_000,
  rateLimitMaxRequests: 30,
  maxUploadSizeMb: 10,
  corsOrigins: getOptionalEnv('CORS_ORIGINS', '*').split(','),
  logLevel: (getOptionalEnv('LOG_LEVEL', 'info') as AppConfig['logLevel']),
};

export function isConfigured(key: keyof AppConfig): boolean {
  const value = config[key];
  if (typeof value === 'string') return value.length > 0;
  return value !== undefined && value !== null;
}
