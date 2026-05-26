import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { apiMiddleware } from '@/lib/api/middleware'
import { success, error } from '@/lib/api/response'
import { apiVersionHeaders } from '@/lib/api/middleware'

// ── GET /v1/webhooks/:webhookId/deliveries ───────────────────────────

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ webhookId: string }> }
) {
  const { webhookId } = await params
  const result = await apiMiddleware(request, {
    requiredScope: 'webhooks:read',
    endpoint: 'GET /v1/webhooks/*/deliveries',
  })

  if (result instanceof NextResponse) return result

  const { apiKey, rateLimitHeaders } = result

  // Verify ownership
  const webhook = await db.webhookSubscription.findFirst({
    where: { id: webhookId, userId: apiKey.userId },
  })

  if (!webhook) {
    return error('NOT_FOUND', 'Webhook subscription not found', 404)
  }

  const url = new URL(request.url)
  const page = Math.max(1, parseInt(url.searchParams.get('page') || '1'))
  const limit = Math.min(50, Math.max(1, parseInt(url.searchParams.get('limit') || '20')))
  const status = url.searchParams.get('status')

  const where: Record<string, unknown> = { webhookId }
  if (status) {
    where.status = status
  }

  const [deliveries, total] = await Promise.all([
    db.webhookDelivery.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      skip: (page - 1) * limit,
      take: limit,
      select: {
        id: true,
        eventId: true,
        eventType: true,
        attemptCount: true,
        maxAttempts: true,
        status: true,
        lastAttemptAt: true,
        nextAttemptAt: true,
        responseStatusCode: true,
        createdAt: true,
      },
    }),
    db.webhookDelivery.count({ where }),
  ])

  const response = success({
    deliveries,
    pagination: {
      page,
      limit,
      total,
      hasMore: page * limit < total,
      totalPages: Math.ceil(total / limit),
    },
  })

  return new NextResponse(response.body, {
    status: response.status,
    headers: {
      ...Object.fromEntries(response.headers.entries()),
      ...rateLimitHeaders,
      ...apiVersionHeaders('1.0.0'),
    },
  })
}
