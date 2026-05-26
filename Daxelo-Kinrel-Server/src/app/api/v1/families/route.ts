import { NextRequest, NextResponse } from 'next/server'
import { z } from 'zod'
import { db } from '@/lib/db'
import { apiMiddleware } from '@/lib/api/middleware'
import { success, collection, error } from '@/lib/api/response'
import { handleIdempotency, storeResponse } from '@/lib/api/idempotency'
import { emit } from '@/lib/api/webhook-delivery'
import { apiVersionHeaders } from '@/lib/api/middleware'

// ── GET /v1/families — List Families ─────────────────────────────────

export async function GET(request: NextRequest) {
  const result = await apiMiddleware(request, {
    requiredScope: 'families:read',
    endpoint: 'GET /v1/families',
  })

  if (result instanceof NextResponse) return result

  const { apiKey, rateLimitHeaders } = result
  const url = new URL(request.url)

  // Pagination
  const page = Math.max(1, parseInt(url.searchParams.get('page') || '1'))
  const limit = Math.min(100, Math.max(1, parseInt(url.searchParams.get('limit') || '20')))
  const sort = url.searchParams.get('sort') || 'createdAt'
  const order = url.searchParams.get('order') || 'desc'

  // Filtering
  const search = url.searchParams.get('search') || ''

  const where: Record<string, unknown> = {}
  if (search) {
    where.OR = [
      { name: { contains: search } },
      { description: { contains: search } },
    ]
  }

  // Only show families the API key owner has access to
  const familyMemberships = await db.familyMember.findMany({
    where: { userId: apiKey.userId },
    select: { familyId: true },
  })
  const familyIds = familyMemberships.map(fm => fm.familyId)

  where.id = { in: familyIds }

  const [families, total] = await Promise.all([
    db.family.findMany({
      where,
      orderBy: { [sort]: order === 'asc' ? 'asc' : 'desc' },
      skip: (page - 1) * limit,
      take: limit,
    }),
    db.family.count({ where }),
  ])

  const response = collection(families, {
    page,
    limit,
    total,
    hasMore: page * limit < total,
  })

  // Add rate limit and version headers
  const headers = {
    ...rateLimitHeaders,
    ...apiVersionHeaders('1.0.0'),
  }

  return new NextResponse(response.body, {
    status: response.status,
    headers: { ...Object.fromEntries(response.headers.entries()), ...headers },
  })
}

// ── POST /v1/families — Create Family ───────────────────────────────

const createFamilySchema = z.object({
  name: z.string().min(1).max(200),
  description: z.string().max(1000).optional(),
  primaryLanguage: z.string().length(2).default('en'),
  gotra: z.string().max(100).optional(),
  originVillage: z.string().max(200).optional(),
})

export async function POST(request: NextRequest) {
  const result = await apiMiddleware(request, {
    requiredScope: 'families:write',
    endpoint: 'POST /v1/families',
  })

  if (result instanceof NextResponse) return result

  const { apiKey, rateLimitHeaders } = result

  // Check idempotency
  const idempotencyKey = request.headers.get('Idempotency-Key')
  if (idempotencyKey) {
    const idemResult = await handleIdempotency(idempotencyKey)
    if (idemResult.isDuplicate && idemResult.response) {
      return new NextResponse(JSON.stringify(idemResult.response.body), {
        status: idemResult.response.status,
        headers: {
          ...rateLimitHeaders,
          ...apiVersionHeaders('1.0.0'),
          ...idemResult.response.headers,
          'X-Idempotent-Replayed': 'true',
        },
      })
    }
  }

  // Parse and validate body
  const bodyResult = await request.json().catch(() => null)
  if (!bodyResult) {
    return error('INVALID_PARAMETER', 'Invalid JSON body', 400)
  }

  const parsed = createFamilySchema.safeParse(bodyResult)
  if (!parsed.success) {
    const details = parsed.error.issues.map(issue => ({
      path: issue.path.join('.'),
      message: issue.message,
    }))
    return error('VALIDATION_ERROR', 'Request validation failed', 400, details)
  }

  const data = parsed.data

  // Create family
  const family = await db.family.create({
    data: {
      name: data.name,
      description: data.description,
      primaryLanguage: data.primaryLanguage,
      gotra: data.gotra,
      originVillage: data.originVillage,
    },
  })

  // Add creator as admin
  await db.familyMember.create({
    data: {
      familyId: family.id,
      userId: apiKey.userId,
      role: 'admin',
    },
  })

  // Emit webhook event
  await emit('family.created', {
    familyId: family.id,
    name: family.name,
  }, family.id)

  // Audit log
  await db.auditLog.create({
    data: {
      userId: apiKey.userId,
      action: 'FAMILY_CREATED',
      resource: 'Family',
      resourceId: family.id,
      details: JSON.stringify({ name: data.name }),
    },
  })

  const response = success(family)

  // Store idempotency response
  if (idempotencyKey) {
    await storeResponse(idempotencyKey, await response.json(), response.status, {})
  }

  const headers = {
    ...rateLimitHeaders,
    ...apiVersionHeaders('1.0.0'),
  }

  return new NextResponse(response.body, {
    status: response.status,
    headers: { ...Object.fromEntries(response.headers.entries()), ...headers },
  })
}
