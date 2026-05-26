import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { apiMiddleware } from '@/lib/api/middleware'
import { success, error } from '@/lib/api/response'
import { emit } from '@/lib/api/webhook-delivery'
import { apiVersionHeaders } from '@/lib/api/middleware'

// ── GET /v1/families/:familyId ───────────────────────────────────────

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ familyId: string }> }
) {
  const { familyId } = await params
  const result = await apiMiddleware(request, {
    requiredScope: 'families:read',
    endpoint: 'GET /v1/families/*',
  })

  if (result instanceof NextResponse) return result

  const { apiKey, rateLimitHeaders } = result
  const url = new URL(request.url)
  const include = url.searchParams.get('include') || ''

  // Check access
  const membership = await db.familyMember.findFirst({
    where: { familyId, userId: apiKey.userId },
  })

  if (!membership) {
    return error('NOT_FOUND', 'Family not found or access denied', 404)
  }

  const family = await db.family.findUnique({
    where: { id: familyId },
    include: {
      members: include.includes('members') ? { include: { user: true } } : false,
      persons: include.includes('members') || include.includes('stats') ? true : false,
      _count: include.includes('stats') ? { select: { persons: true, members: true } } : undefined,
    } as never,
  })

  if (!family) {
    return error('NOT_FOUND', 'Family not found', 404)
  }

  let responseData: Record<string, unknown> = { ...family }

  if (include.includes('stats')) {
    const persons = (family as Record<string, unknown>).persons as Array<{ isDeceased: boolean }> || []
    const living = persons.filter((p) => !p.isDeceased)
    const deceased = persons.filter((p) => p.isDeceased)

    responseData.stats = {
      totalPersons: persons.length,
      livingCount: living.length,
      deceasedCount: deceased.length,
      memberCount: ((family as Record<string, unknown>)._count as { members: number })?.members || 0,
    }
  }

  // Remove persons array if not requested
  if (!include.includes('members') && !include.includes('stats')) {
    delete responseData.persons
  }

  const response = success(responseData)

  return new NextResponse(response.body, {
    status: response.status,
    headers: {
      ...Object.fromEntries(response.headers.entries()),
      ...rateLimitHeaders,
      ...apiVersionHeaders('1.0.0'),
    },
  })
}

// ── PATCH /v1/families/:familyId ─────────────────────────────────────

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ familyId: string }> }
) {
  const { familyId } = await params
  const result = await apiMiddleware(request, {
    requiredScope: 'families:write',
    endpoint: 'PATCH /v1/families/*',
  })

  if (result instanceof NextResponse) return result

  const { apiKey, rateLimitHeaders } = result

  // Check admin access
  const membership = await db.familyMember.findFirst({
    where: { familyId, userId: apiKey.userId, role: 'admin' },
  })

  if (!membership) {
    return error('INSUFFICIENT_SCOPE', 'Admin access required to update family', 403)
  }

  const body = await request.json().catch(() => null)
  if (!body) {
    return error('INVALID_PARAMETER', 'Invalid JSON body', 400)
  }

  const allowedFields = ['name', 'description', 'primaryLanguage', 'gotra', 'originVillage']
  const updateData: Record<string, unknown> = {}

  for (const field of allowedFields) {
    if (body[field] !== undefined) {
      updateData[field] = body[field]
    }
  }

  if (Object.keys(updateData).length === 0) {
    return error('VALIDATION_ERROR', 'No valid fields to update', 400)
  }

  const family = await db.family.update({
    where: { id: familyId },
    data: updateData,
  })

  // Emit webhook event
  await emit('family.updated', {
    familyId,
    changedFields: Object.keys(updateData),
  }, familyId)

  // Audit log
  await db.auditLog.create({
    data: {
      userId: apiKey.userId,
      action: 'FAMILY_UPDATED',
      resource: 'Family',
      resourceId: familyId,
      details: JSON.stringify({ changedFields: Object.keys(updateData) }),
    },
  })

  const response = success(family)

  return new NextResponse(response.body, {
    status: response.status,
    headers: {
      ...Object.fromEntries(response.headers.entries()),
      ...rateLimitHeaders,
      ...apiVersionHeaders('1.0.0'),
    },
  })
}

// ── DELETE /v1/families/:familyId ────────────────────────────────────

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ familyId: string }> }
) {
  const { familyId } = await params
  const result = await apiMiddleware(request, {
    requiredScope: 'families:write',
    endpoint: 'DELETE /v1/families/*',
  })

  if (result instanceof NextResponse) return result

  const { apiKey, rateLimitHeaders } = result

  // Check admin access
  const membership = await db.familyMember.findFirst({
    where: { familyId, userId: apiKey.userId, role: 'admin' },
  })

  if (!membership) {
    return error('INSUFFICIENT_SCOPE', 'Admin access required to delete family', 403)
  }

  // Get cascade counts before deletion
  const [personCount, memberCount, relationshipCount] = await Promise.all([
    db.person.count({ where: { familyId } }),
    db.familyMember.count({ where: { familyId } }),
    db.relationship.count({ where: { familyId } }),
  ])

  // Delete family (cascade will handle related records)
  await db.family.delete({
    where: { id: familyId },
  })

  // Emit webhook event
  await emit('family.deleted', { familyId })

  // Audit log
  await db.auditLog.create({
    data: {
      userId: apiKey.userId,
      action: 'FAMILY_DELETED',
      resource: 'Family',
      resourceId: familyId,
      details: JSON.stringify({ personCount, memberCount, relationshipCount }),
    },
  })

  const response = success({
    deleted: true,
    familyId,
    cascadeCounts: {
      persons: personCount,
      members: memberCount,
      relationships: relationshipCount,
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
