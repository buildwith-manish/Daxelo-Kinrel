import { NextRequest, NextResponse } from 'next/server'
import { z } from 'zod'
import { db } from '@/lib/db'
import { apiMiddleware } from '@/lib/api/middleware'
import { success, collection, error } from '@/lib/api/response'
import { createWebhookSubscription, EVENT_TYPES, type WebhookEventType } from '@/lib/api/webhook-delivery'
import { TIER_LIMITS } from '@/lib/api/api-key'
import { apiVersionHeaders } from '@/lib/api/middleware'

// ── GET /v1/webhooks ─────────────────────────────────────────────────

export async function GET(request: NextRequest) {
  const result = await apiMiddleware(request, {
    requiredScope: 'webhooks:read',
    endpoint: 'GET /v1/webhooks',
  })

  if (result instanceof NextResponse) return result

  const { apiKey, rateLimitHeaders } = result

  const url = new URL(request.url)
  const page = Math.max(1, parseInt(url.searchParams.get('page') || '1'))
  const limit = Math.min(50, Math.max(1, parseInt(url.searchParams.get('limit') || '20')))

  const [webhooks, total] = await Promise.all([
    db.webhookSubscription.findMany({
      where: { userId: apiKey.userId },
      orderBy: { createdAt: 'desc' },
      skip: (page - 1) * limit,
      take: limit,
      include: {
        _count: {
          select: { deliveries: true },
        },
      },
    }),
    db.webhookSubscription.count({
      where: { userId: apiKey.userId },
    }),
  ])

  const sanitizedWebhooks = webhooks.map(wh => ({
    id: wh.id,
    url: wh.url,
    events: JSON.parse(wh.events),
    active: wh.active,
    description: wh.description,
    deliveryCount: wh._count.deliveries,
    createdAt: wh.createdAt,
    updatedAt: wh.updatedAt,
    // Don't expose the secret
  }))

  const response = collection(sanitizedWebhooks, {
    page,
    limit,
    total,
    hasMore: page * limit < total,
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

// ── POST /v1/webhooks ────────────────────────────────────────────────

const createWebhookSchema = z.object({
  url: z.string().url(),
  events: z.array(z.string()).min(1),
  description: z.string().max(500).optional(),
  secret: z.string().min(16).max(128).optional(),
})

export async function POST(request: NextRequest) {
  const result = await apiMiddleware(request, {
    requiredScope: 'webhooks:manage',
    endpoint: 'POST /v1/webhooks',
  })

  if (result instanceof NextResponse) return result

  const { apiKey, rateLimitHeaders } = result

  const body = await request.json().catch(() => null)
  if (!body) {
    return error('INVALID_PARAMETER', 'Invalid JSON body', 400)
  }

  const parsed = createWebhookSchema.safeParse(body)
  if (!parsed.success) {
    const details = parsed.error.issues.map(issue => ({
      path: issue.path.join('.'),
      message: issue.message,
    }))
    return error('VALIDATION_ERROR', 'Request validation failed', 400, details)
  }

  const data = parsed.data

  // Validate event types
  const validEvents = Object.keys(EVENT_TYPES)
  const invalidEvents = data.events.filter(e => !validEvents.includes(e) && e !== '*')
  if (invalidEvents.length > 0) {
    return error('INVALID_PARAMETER', `Invalid event types: ${invalidEvents.join(', ')}`, 400, {
      validEvents,
    })
  }

  // Check webhook limit based on tier
  const tierConfig = TIER_LIMITS[apiKey.tier as keyof typeof TIER_LIMITS] || TIER_LIMITS.free
  const existingWebhooks = await db.webhookSubscription.count({
    where: { userId: apiKey.userId, active: true },
  })

  if (existingWebhooks >= tierConfig.maxWebhooks) {
    return error('CONFLICT', `Maximum ${tierConfig.maxWebhooks} webhooks allowed for ${apiKey.tier} tier`, 409, {
      current: existingWebhooks,
      max: tierConfig.maxWebhooks,
    })
  }

  const subscription = await createWebhookSubscription(
    apiKey.userId,
    data.url,
    data.events,
    data.secret
  )

  const response = success({
    id: subscription.id,
    url: subscription.url,
    events: JSON.parse(subscription.events),
    active: subscription.active,
    description: subscription.description,
    createdAt: subscription.createdAt,
    // Include secret only on creation
    secret: subscription.secret,
    warning: 'Store this webhook secret securely. It will not be shown again.',
  })

  // Audit log
  await db.auditLog.create({
    data: {
      userId: apiKey.userId,
      action: 'WEBHOOK_CREATED',
      resource: 'WebhookSubscription',
      resourceId: subscription.id,
      details: JSON.stringify({ url: data.url, events: data.events }),
    },
  })

  return new NextResponse(response.body, {
    status: 201,
    headers: {
      ...Object.fromEntries(response.headers.entries()),
      ...rateLimitHeaders,
      ...apiVersionHeaders('1.0.0'),
    },
  })
}
