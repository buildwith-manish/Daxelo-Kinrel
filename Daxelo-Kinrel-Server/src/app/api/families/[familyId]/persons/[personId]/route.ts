// DAXELO KINREL — Pack 02: Single Person API (Internal, Session Auth)
// GET/PATCH/DELETE /api/families/:familyId/persons/:personId

import { getServerSession } from 'next-auth'
import { authOptions } from '@/lib/auth'
import { db } from '@/lib/db'
import { NextRequest, NextResponse } from 'next/server'
import { z } from 'zod'
import { validateAndNormalizeKey } from '@/lib/kinship-validator'

// ── Auth Helpers ────────────────────────────────────────────────────

async function requireAuth() {
  const session = await getServerSession(authOptions)
  if (!session?.user?.id) return null
  return session
}

async function requireFamilyMember(familyId: string, userId: string, minRole?: string[]) {
  const membership = await db.familyMember.findUnique({
    where: { familyId_userId: { familyId, userId } },
  })
  if (!membership) return null
  if (minRole && !minRole.includes(membership.role)) return null
  return membership
}

// ── GET /api/families/:familyId/persons/:personId ───────────────────

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ familyId: string; personId: string }> }
) {
  const session = await requireAuth()
  if (!session) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const { familyId, personId } = await params

  const membership = await requireFamilyMember(familyId, session.user.id)
  if (!membership) {
    return NextResponse.json({ error: 'Family not found or access denied' }, { status: 404 })
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
    return NextResponse.json({ error: 'Person not found' }, { status: 404 })
  }

  return NextResponse.json({ data: person })
}

// ── PATCH /api/families/:familyId/persons/:personId ─────────────────

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
  const session = await requireAuth()
  if (!session) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const { familyId, personId } = await params

  // Editor or above required
  const membership = await requireFamilyMember(familyId, session.user.id, ['admin', 'editor'])
  if (!membership) {
    const baseMembership = await requireFamilyMember(familyId, session.user.id)
    if (!baseMembership) {
      return NextResponse.json({ error: 'Family not found or access denied' }, { status: 404 })
    }
    return NextResponse.json({ error: 'Editor role or above required to update persons' }, { status: 403 })
  }

  // Verify person exists and is not soft-deleted
  const existingPerson = await db.person.findFirst({
    where: { id: personId, familyId, deletedAt: null },
  })

  if (!existingPerson) {
    return NextResponse.json({ error: 'Person not found' }, { status: 404 })
  }

  // Parse body
  const body = await request.json().catch(() => null)
  if (!body) {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 })
  }

  const parsed = updatePersonSchema.safeParse(body)
  if (!parsed.success) {
    return NextResponse.json({
      error: 'Validation failed',
      details: parsed.error.issues.map(issue => ({
        path: issue.path.join('.'),
        message: issue.message,
      })),
    }, { status: 400 })
  }

  const data = parsed.data

  // Validate relationship key if provided
  if (data.relationship) {
    const normalizedKey = validateAndNormalizeKey(data.relationship)
    if (!normalizedKey) {
      return NextResponse.json({
        error: `Invalid relationship key: "${data.relationship}". Please provide a valid kinship term.`,
      }, { status: 422 })
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
    return NextResponse.json({ error: 'No valid fields to update' }, { status: 400 })
  }

  const updatedPerson = await db.person.update({
    where: { id: personId },
    data: updateData,
  })

  // Audit log
  await db.auditLog.create({
    data: {
      userId: session.user.id,
      action: 'PERSON_UPDATED',
      resource: 'Person',
      resourceId: personId,
      details: JSON.stringify({ changedFields: Object.keys(updateData) }),
    },
  })

  return NextResponse.json({ data: updatedPerson })
}

// ── DELETE /api/families/:familyId/persons/:personId (soft delete) ──

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ familyId: string; personId: string }> }
) {
  const session = await requireAuth()
  if (!session) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const { familyId, personId } = await params

  // Admin only
  const membership = await requireFamilyMember(familyId, session.user.id, ['admin'])
  if (!membership) {
    const baseMembership = await requireFamilyMember(familyId, session.user.id)
    if (!baseMembership) {
      return NextResponse.json({ error: 'Family not found or access denied' }, { status: 404 })
    }
    return NextResponse.json({ error: 'Admin role required to delete persons' }, { status: 403 })
  }

  // Verify person exists and is not already soft-deleted
  const existingPerson = await db.person.findFirst({
    where: { id: personId, familyId, deletedAt: null },
  })

  if (!existingPerson) {
    return NextResponse.json({ error: 'Person not found' }, { status: 404 })
  }

  // Soft delete
  await db.person.update({
    where: { id: personId },
    data: { deletedAt: new Date() },
  })

  // Audit log
  await db.auditLog.create({
    data: {
      userId: session.user.id,
      action: 'PERSON_DELETED',
      resource: 'Person',
      resourceId: personId,
      details: JSON.stringify({ softDelete: true, familyId }),
    },
  })

  return new NextResponse(null, { status: 204 })
}
