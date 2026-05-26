import { NextRequest, NextResponse } from 'next/server'
import { getServerSession } from 'next-auth'
import { authOptions } from '@/lib/auth'
import { db } from '@/lib/db'

// ── GET /api/families/:familyId — Single family with counts ─────────────

export async function GET(
  _request: NextRequest,
  { params }: { params: Promise<{ familyId: string }> }
) {
  const session = await getServerSession(authOptions)

  if (!session?.user?.id) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const { familyId } = await params

  // Check access
  const membership = await db.familyMember.findFirst({
    where: { familyId, userId: session.user.id },
  })

  if (!membership) {
    return NextResponse.json(
      { error: 'Family not found or access denied' },
      { status: 404 }
    )
  }

  const family = await db.family.findUnique({
    where: { id: familyId },
    include: {
      _count: {
        select: { members: true, persons: true },
      },
    },
  })

  if (!family) {
    return NextResponse.json({ error: 'Family not found' }, { status: 404 })
  }

  return NextResponse.json({
    family: {
      id: family.id,
      name: family.name,
      description: family.description,
      primaryLanguage: family.primaryLanguage,
      gotra: family.gotra,
      originVillage: family.originVillage,
      memberCount: family._count.members,
      personCount: family._count.persons,
      createdAt: family.createdAt,
      updatedAt: family.updatedAt,
    },
    role: membership.role,
  })
}

// ── PATCH /api/families/:familyId — Update family (admin only) ─────────

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ familyId: string }> }
) {
  const session = await getServerSession(authOptions)

  if (!session?.user?.id) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const { familyId } = await params

  // Check admin access
  const membership = await db.familyMember.findFirst({
    where: { familyId, userId: session.user.id, role: 'admin' },
  })

  if (!membership) {
    return NextResponse.json(
      { error: 'Admin access required to update family' },
      { status: 403 }
    )
  }

  const body = await request.json().catch(() => null)
  if (!body) {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 })
  }

  const allowedFields = [
    'name',
    'description',
    'primaryLanguage',
    'gotra',
    'originVillage',
  ]
  const updateData: Record<string, unknown> = {}

  for (const field of allowedFields) {
    if (body[field] !== undefined) {
      updateData[field] = body[field]
    }
  }

  if (Object.keys(updateData).length === 0) {
    return NextResponse.json(
      { error: 'No valid fields to update' },
      { status: 400 }
    )
  }

  const family = await db.family.update({
    where: { id: familyId },
    data: updateData,
  })

  // Audit log
  await db.auditLog.create({
    data: {
      userId: session.user.id,
      action: 'FAMILY_UPDATED',
      resource: 'Family',
      resourceId: familyId,
      details: JSON.stringify({ changedFields: Object.keys(updateData) }),
    },
  })

  return NextResponse.json({ family })
}

// ── DELETE /api/families/:familyId — Delete family (admin only) ─────────

export async function DELETE(
  _request: NextRequest,
  { params }: { params: Promise<{ familyId: string }> }
) {
  const session = await getServerSession(authOptions)

  if (!session?.user?.id) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const { familyId } = await params

  // Check admin access
  const membership = await db.familyMember.findFirst({
    where: { familyId, userId: session.user.id, role: 'admin' },
  })

  if (!membership) {
    return NextResponse.json(
      { error: 'Admin access required to delete family' },
      { status: 403 }
    )
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

  // Audit log
  await db.auditLog.create({
    data: {
      userId: session.user.id,
      action: 'FAMILY_DELETED',
      resource: 'Family',
      resourceId: familyId,
      details: JSON.stringify({
        personCount,
        memberCount,
        relationshipCount,
      }),
    },
  })

  return NextResponse.json({
    deleted: true,
    familyId,
    cascadeCounts: {
      persons: personCount,
      members: memberCount,
      relationships: relationshipCount,
    },
  })
}
