// DAXELO KINREL — Pack 02: Single Person API
// GET/PATCH/DELETE /v1/families/:familyId/persons/:personId (API Key auth)

import { NextRequest, NextResponse } from 'next/server'
import { z } from 'zod'
import { db } from '@/lib/db'
import { apiMiddleware } from '@/lib/api/middleware'
import { success, error } from '@/lib/api/response'
import { emit } from '@/lib/api/webhook-delivery'
import { apiVersionHeaders } from '@/lib/api/middleware'
import { validateAndNormalizeKey } from '@/lib/kinship-validator'

// ── GET /v1/families/:familyId/persons/:personId ────────────────────

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ familyId: string; personId: string }> }
) {
  const { familyId, personId } = await params
  const result = await apiMiddleware(request, {
    requiredScope: 'persons:read',
    endpoint: 'GET /v1/families/*/persons/*',
  })

  if (result instanceof NextResponse) return result

  const { apiKey, rateLimitHeaders } = result

  // Check access
  const membership = await db.familyMember.findUnique({
    where: { familyId_userId: { familyId, userId: apiKey.userId } },
  })

  if (!membership) {
    return error('NOT_FOUND', 'Family not found or access denied', 404)
  }

  const person = await db.person.findFirst({
    where: {
      id: personId,
      familyId,
      deletedAt: null,
    },
    include: {
      relationshipsFrom: true,
      relationshipsTo: true,
    },
  })

  if (!person) {
    return error('NOT_FOUND', 'Person not found', 404)
  }

  const response = success(person)

  return new NextResponse(response.body, {
    status: response.status,
    headers: {
      ...Object.fromEntries(response.headers.entries()),
      ...rateLimitHeaders,
      ...apiVersionHeaders('1.0.0'),
    },
  })
}

// ── PATCH /v1/families/:familyId/persons/:personId ──────────────────

const updatePersonSchema = z.object({
  name: z.string().min(1).max(200).optional(),
  relationship: z.string().min(1).max(100).optional(),
  dateOfBirth: z.string().nullable().optional(),
  gotra: z.string().max(100).nullable().optional(),
  occupation: z.string().max(200).nullable().optional(),
  city: z.string().max(200).nullable().optional(),
  isDeceased: z.boolean().optional(),
  privacyLevel: z.enum(['family', 'extended', 'public']).optional(),
})

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ familyId: string; personId: string }> }
) {
  const { familyId, personId } = await params
  const result = await apiMiddleware(request, {
    requiredScope: 'persons:write',
    endpoint: 'PATCH /v1/families/*/persons/*',
  })

  if (result instanceof NextResponse) return result

  const { apiKey, rateLimitHeaders } = result

  // Check access — editor or above
  const membership = await db.familyMember.findUnique({
    where: { familyId_userId: { familyId, userId: apiKey.userId } },
  })

  if (!membership) {
    return error('NOT_FOUND', 'Family not found or access denied', 404)
  }

  if (!['admin', 'editor'].includes(membership.role)) {
    return error('INSUFFICIENT_SCOPE', 'Editor role or above required to update persons', 403)
  }

  // Verify person exists and is not soft-deleted
  const existingPerson = await db.person.findFirst({
    where: { id: personId, familyId, deletedAt: null },
  })

  if (!existingPerson) {
    return error('NOT_FOUND', 'Person not found', 404)
  }

  // Parse body
  const body = await request.json().catch(() => null)
  if (!body) {
    return error('INVALID_PARAMETER', 'Invalid JSON body', 400)
  }

  const parsed = updatePersonSchema.safeParse(body)
  if (!parsed.success) {
    const details = parsed.error.issues.map(issue => ({
      path: issue.path.join('.'),
      message: issue.message,
    }))
    return error('VALIDATION_ERROR', 'Request validation failed', 400, details)
  }

  const data = parsed.data

  // Validate relationship key if provided
  if (data.relationship) {
    const normalizedKey = validateAndNormalizeKey(data.relationship)
    if (!normalizedKey) {
      return error('VALIDATION_ERROR', `Invalid relationship key: "${data.relationship}". Please provide a valid kinship term.`, 422)
    }
    data.relationship = normalizedKey
  }

  // Build update data
  const updateData: any = {}

  if (data.name !== undefined) updateData.name = data.name
  if (data.relationship !== undefined) updateData.relationship = data.relationship
  if (data.dateOfBirth !== undefined) updateData.dateOfBirth = data.dateOfBirth ? new Date(data.dateOfBirth) : null
  if (data.gotra !== undefined) updateData.gotra = data.gotra
  if (data.occupation !== undefined) updateData.occupation = data.occupation
  if (data.city !== undefined) updateData.city = data.city
  if (data.isDeceased !== undefined) updateData.isDeceased = data.isDeceased
  if (data.privacyLevel !== undefined) updateData.privacyLevel = data.privacyLevel

  if (Object.keys(updateData).length === 0) {
    return error('VALIDATION_ERROR', 'No valid fields to update', 400)
  }

  const updatedPerson = await db.person.update({
    where: { id: personId },
    data: updateData,
  })

  // Emit webhook event
  await emit('person.updated', {
    personId: updatedPerson.id,
    familyId,
    changedFields: Object.keys(updateData),
  }, familyId)

  // Audit log
  await db.auditLog.create({
    data: {
      userId: apiKey.userId,
      action: 'PERSON_UPDATED',
      resource: 'Person',
      resourceId: personId,
      details: JSON.stringify({ changedFields: Object.keys(updateData) }),
    },
  })

  const response = success(updatedPerson)

  return new NextResponse(response.body, {
    status: response.status,
    headers: {
      ...Object.fromEntries(response.headers.entries()),
      ...rateLimitHeaders,
      ...apiVersionHeaders('1.0.0'),
    },
  })
}

// ── DELETE /v1/families/:familyId/persons/:personId (soft delete) ───

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ familyId: string; personId: string }> }
) {
  const { familyId, personId } = await params
  const result = await apiMiddleware(request, {
    requiredScope: 'persons:write',
    endpoint: 'DELETE /v1/families/*/persons/*',
  })

  if (result instanceof NextResponse) return result

  const { apiKey, rateLimitHeaders } = result

  // Check access — admin only
  const membership = await db.familyMember.findUnique({
    where: { familyId_userId: { familyId, userId: apiKey.userId } },
  })

  if (!membership) {
    return error('NOT_FOUND', 'Family not found or access denied', 404)
  }

  if (membership.role !== 'admin') {
    return error('INSUFFICIENT_SCOPE', 'Admin role required to delete persons', 403)
  }

  // Verify person exists and is not already soft-deleted
  const existingPerson = await db.person.findFirst({
    where: { id: personId, familyId, deletedAt: null },
  })

  if (!existingPerson) {
    return error('NOT_FOUND', 'Person not found', 404)
  }

  // Soft delete
  await db.person.update({
    where: { id: personId },
    data: { deletedAt: new Date() },
  })

  // Emit webhook event
  await emit('person.deleted', {
    personId,
    familyId,
  }, familyId)

  // Audit log
  await db.auditLog.create({
    data: {
      userId: apiKey.userId,
      action: 'PERSON_DELETED',
      resource: 'Person',
      resourceId: personId,
      details: JSON.stringify({ softDelete: true, familyId }),
    },
  })

  return new NextResponse(null, {
    status: 204,
    headers: {
      ...rateLimitHeaders,
      ...apiVersionHeaders('1.0.0'),
    },
  })
}
