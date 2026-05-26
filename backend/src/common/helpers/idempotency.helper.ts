import { PrismaService } from '../../prisma/prisma.service';

/**
 * 24-hour TTL DB-backed idempotency helper
 * Uses the IdempotencyKey model in Prisma to store and retrieve
 * previous responses for idempotent API calls.
 */

const IDEMPOTENCY_TTL_MS = 24 * 60 * 60 * 1000; // 24 hours

export interface IdempotencyResponse {
  body: any;
  status: number;
  headers: Record<string, string>;
}

/**
 * Handle idempotency: check if a request with this key has already been processed
 * @param prisma - PrismaService instance
 * @param key - Idempotency key from request header
 * @returns Previous response if found, null otherwise
 */
export async function handleIdempotency(
  prisma: PrismaService,
  key: string,
): Promise<IdempotencyResponse | null> {
  if (!key) return null;

  const existing = await prisma.idempotencyKey.findUnique({
    where: { key },
  });

  if (!existing) return null;

  // Check if the stored response has expired
  if (existing.expiresAt < new Date()) {
    // Clean up expired entry
    await prisma.idempotencyKey.delete({ where: { key } }).catch(() => {});
    return null;
  }

  return {
    body: JSON.parse(existing.responseBody),
    status: existing.responseStatus,
    headers: JSON.parse(existing.responseHeaders),
  };
}

/**
 * Store a response for idempotency
 * @param prisma - PrismaService instance
 * @param key - Idempotency key from request header
 * @param body - Response body to store
 * @param status - HTTP status code
 * @param headers - Response headers to store
 */
export async function storeResponse(
  prisma: PrismaService,
  key: string,
  body: any,
  status: number,
  headers: Record<string, string> = {},
): Promise<void> {
  if (!key) return;

  const expiresAt = new Date(Date.now() + IDEMPOTENCY_TTL_MS);

  await prisma.idempotencyKey.upsert({
    where: { key },
    create: {
      key,
      responseBody: JSON.stringify(body),
      responseStatus: status,
      responseHeaders: JSON.stringify(headers),
      expiresAt,
    },
    update: {
      responseBody: JSON.stringify(body),
      responseStatus: status,
      responseHeaders: JSON.stringify(headers),
      expiresAt,
    },
  });
}

/**
 * Clean up expired idempotency keys
 * Should be called periodically (e.g., via cron or scheduler)
 * @param prisma - PrismaService instance
 */
export async function cleanupExpiredIdempotencyKeys(
  prisma: PrismaService,
): Promise<number> {
  const result = await prisma.idempotencyKey.deleteMany({
    where: {
      expiresAt: {
        lt: new Date(),
      },
    },
  });

  return result.count;
}
