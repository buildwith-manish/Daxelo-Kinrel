// DAXELO KINREL — Pack 09: User Profile API
// GET + PATCH + DELETE /api/users/me

import { NextRequest, NextResponse } from 'next/server'
import { getServerSession } from 'next-auth'
import { authOptions } from '@/lib/auth'
import { db } from '@/lib/db'
import { z } from 'zod'

// ── GET: Current user profile ────────────────────────────────────────

export async function GET() {
  const session = await getServerSession(authOptions)
  if (!session?.user?.id) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const user = await db.user.findUnique({
    where: { id: session.user.id },
    select: {
      id: true,
      email: true,
      name: true,
      phone: true,
      preferredLanguage: true,
      role: true,
      createdAt: true,
      updatedAt: true,
    },
  })

  if (!user) {
    return NextResponse.json({ error: 'User not found' }, { status: 404 })
  }

  return NextResponse.json({ user })
}

// ── PATCH: Update user profile ───────────────────────────────────────

const updateUserSchema = z.object({
  name: z.string().min(1).max(200).optional(),
  phone: z.string().max(50).nullable().optional(),
  preferredLanguage: z.string().max(10).optional(),
})

export async function PATCH(request: NextRequest) {
  const session = await getServerSession(authOptions)
  if (!session?.user?.id) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const body = await request.json().catch(() => null)
  if (!body) {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 422 })
  }

  const parsed = updateUserSchema.safeParse(body)
  if (!parsed.success) {
    return NextResponse.json(
      {
        error: 'Validation failed',
        details: parsed.error.issues.map((i) => ({
          path: i.path.join('.'),
          message: i.message,
        })),
      },
      { status: 422 }
    )
  }

  const data = parsed.data

  const updateData: Record<string, unknown> = {}
  if (data.name !== undefined) updateData.name = data.name
  if (data.phone !== undefined) updateData.phone = data.phone
  if (data.preferredLanguage !== undefined) updateData.preferredLanguage = data.preferredLanguage

  if (Object.keys(updateData).length === 0) {
    return NextResponse.json({ error: 'No fields to update' }, { status: 422 })
  }

  const user = await db.user.update({
    where: { id: session.user.id },
    data: updateData,
    select: {
      id: true,
      email: true,
      name: true,
      phone: true,
      preferredLanguage: true,
      role: true,
    },
  })

  return NextResponse.json({ user })
}

// ── DELETE: Delete account ───────────────────────────────────────────

export async function DELETE() {
  const session = await getServerSession(authOptions)
  if (!session?.user?.id) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const userId = session.user.id

  // Hard delete with cascade — remove all user data
  // In production, you might want soft delete instead
  try {
    // Delete in order of foreign key dependencies
    await db.notificationPreference.deleteMany({ where: { userId } })
    await db.notification.deleteMany({ where: { userId } })
    await db.whatsAppConsent.deleteMany({ where: { userId } })
    await db.familyMember.deleteMany({ where: { userId } })
    await db.apiKey.deleteMany({ where: { userId } })
    await db.subscription.deleteMany({ where: { userId } })
    await db.supportTicket.deleteMany({ where: { userId } })
    await db.invitation.deleteMany({ where: { inviterId: userId } })

    // Finally delete the user
    await db.user.delete({ where: { id: userId } })

    return NextResponse.json({ success: true, message: 'Account deleted' })
  } catch (error) {
    console.error('[DELETE /api/users/me] Error:', error)
    return NextResponse.json({ error: 'Failed to delete account' }, { status: 500 })
  }
}
