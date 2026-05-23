import { db } from '@/lib/db'

// ── Idempotency Handler ──────────────────────────────────────────────
// Stores API responses for idempotent requests (24-hour TTL)

const IDEMPOTENCY_TTL_MS = 24 * 60 * 60 * 1000 // 24 hours

// ── Handle Idempotency Check ─────────────────────────────────────────

export async function handleIdempotency(
  key: string
): Promise<{
  isDuplicate: boolean
  response?: { body: unknown; status: number; headers: Record<string, string> }
}> {
  const existing = await db.idempotencyKey.findUnique({
    where: { key },
  })

  if (!existing) {
    return { isDuplicate: false }
  }

  // Check if expired
  if (new Date() > existing.expiresAt) {
    // Clean up expired entry
    await db.idempotencyKey.delete({ where: { key } }).catch(() => {})
    return { isDuplicate: false }
  }

  // Return cached response
  let parsedBody: unknown
  try {
    parsedBody = JSON.parse(existing.responseBody)
  } catch {
    parsedBody = existing.responseBody
  }

  let parsedHeaders: Record<string, string> = {}
  try {
    parsedHeaders = JSON.parse(existing.responseHeaders)
  } catch {
    // Use empty headers
  }

  return {
    isDuplicate: true,
    response: {
      body: parsedBody,
      status: existing.responseStatus,
      headers: parsedHeaders,
    },
  }
}

// ── Store Response for Idempotency ───────────────────────────────────

export async function storeResponse(
  key: string,
  body: unknown,
  status: number,
  headers: Record<string, string>
): Promise<void> {
  const expiresAt = new Date(Date.now() + IDEMPOTENCY_TTL_MS)

  await db.idempotencyKey.upsert({
    where: { key },
    create: {
      key,
      responseBody: typeof body === 'string' ? body : JSON.stringify(body),
      responseStatus: status,
      responseHeaders: JSON.stringify(headers),
      expiresAt,
    },
    update: {
      responseBody: typeof body === 'string' ? body : JSON.stringify(body),
      responseStatus: status,
      responseHeaders: JSON.stringify(headers),
      expiresAt,
    },
  })
}

// ── Cleanup Expired Keys ─────────────────────────────────────────────

export async function cleanupExpired(): Promise<number> {
  const result = await db.idempotencyKey.deleteMany({
    where: {
      expiresAt: { lt: new Date() },
    },
  })
  return result.count
}
