// DAXELO KINREL — Family Invitations API
// Pack 04: WhatsApp Platform — API Route

import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import crypto from 'crypto'

// ── GET: List Invitations for a Family ───────────────────────────

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url)
    const familyId = searchParams.get('familyId')
    const status = searchParams.get('status')

    if (!familyId) {
      return NextResponse.json(
        { error: 'familyId query parameter is required' },
        { status: 400 },
      )
    }

    const where: Record<string, unknown> = { familyId }
    if (status) {
      where.status = status
    }

    const invitations = await db.invitation.findMany({
      where,
      include: {
        inviter: {
          select: { id: true, name: true, email: true, phone: true },
        },
        family: {
          select: { id: true, name: true, primaryLanguage: true },
        },
      },
      orderBy: { createdAt: 'desc' },
    })

    // Parse JSON preFilledData for client convenience
    const parsedInvitations = invitations.map((inv) => ({
      ...inv,
      preFilledData: JSON.parse(inv.preFilledData) as Record<string, unknown>,
    }))

    return NextResponse.json(
      { invitations: parsedInvitations },
      { status: 200 },
    )
  } catch (error) {
    console.error('[Invitations GET] Error:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 },
    )
  }
}

// ── POST: Create a New Invitation ────────────────────────────────

interface CreateInvitationBody {
  familyId: string
  inviterId: string
  recipientEmail?: string
  recipientPhone?: string
  recipientName?: string
  role?: 'admin' | 'editor' | 'member' | 'viewer'
  channel?: 'email' | 'whatsapp' | 'direct_link'
  preFilledData?: Record<string, unknown>
}

export async function POST(request: NextRequest) {
  try {
    const body: CreateInvitationBody = await request.json()
    const {
      familyId,
      inviterId,
      recipientEmail,
      recipientPhone,
      recipientName,
      role,
      channel,
      preFilledData,
    } = body

    if (!familyId || !inviterId) {
      return NextResponse.json(
        { error: 'familyId and inviterId are required' },
        { status: 400 },
      )
    }

    // Verify family exists
    const family = await db.family.findUnique({ where: { id: familyId } })
    if (!family) {
      return NextResponse.json(
        { error: 'Family not found' },
        { status: 404 },
      )
    }

    // Verify inviter is a member of the family
    const membership = await db.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId: inviterId } },
    })
    if (!membership) {
      return NextResponse.json(
        { error: 'Inviter is not a member of this family' },
        { status: 403 },
      )
    }

    // Generate unique token
    const token = crypto.randomUUID()

    const now = new Date()

    // Determine if WhatsApp sent timestamp should be set
    const isWhatsapp = channel === 'whatsapp'

    // Create invitation record
    const invitation = await db.invitation.create({
      data: {
        token,
        familyId,
        inviterId,
        recipientEmail: recipientEmail ?? null,
        recipientPhone: recipientPhone ?? null,
        recipientName: recipientName ?? null,
        status: 'pending',
        role: role ?? 'member',
        channel: channel ?? 'email',
        preFilledData: JSON.stringify(preFilledData ?? {}),
        whatsappSentAt: isWhatsapp ? now : null,
        expiresAt: new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000), // 7 days
      },
      include: {
        inviter: {
          select: { id: true, name: true, email: true },
        },
        family: {
          select: { id: true, name: true },
        },
      },
    })

    // Build deep link
    const appBaseUrl = process.env.NEXT_PUBLIC_APP_URL ?? 'https://daxelo.app'
    const deepLink = `${appBaseUrl}/invite/${token}`

    // Parse JSON for response
    const parsedInvitation = {
      ...invitation,
      preFilledData: JSON.parse(invitation.preFilledData) as Record<string, unknown>,
      deepLink,
    }

    return NextResponse.json(
      { invitation: parsedInvitation },
      { status: 201 },
    )
  } catch (error) {
    console.error('[Invitations POST] Error:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 },
    )
  }
}

// ── PATCH: Accept an Invitation ──────────────────────────────────

interface AcceptInvitationBody {
  token: string
}

export async function PATCH(request: NextRequest) {
  try {
    const body: AcceptInvitationBody = await request.json()
    const { token } = body

    if (!token) {
      return NextResponse.json(
        { error: 'token is required' },
        { status: 400 },
      )
    }

    const invitation = await db.invitation.findUnique({
      where: { token },
    })

    if (!invitation) {
      return NextResponse.json(
        { error: 'Invitation not found' },
        { status: 404 },
      )
    }

    if (invitation.status !== 'pending') {
      return NextResponse.json(
        { error: `Invitation is already ${invitation.status}` },
        { status: 400 },
      )
    }

    // Check if invitation has expired
    if (invitation.expiresAt && new Date() > invitation.expiresAt) {
      await db.invitation.update({
        where: { id: invitation.id },
        data: { status: 'expired' },
      })
      return NextResponse.json(
        { error: 'Invitation has expired' },
        { status: 400 },
      )
    }

    const now = new Date()

    // Update invitation status
    const updated = await db.invitation.update({
      where: { id: invitation.id },
      data: {
        status: 'accepted',
        acceptedAt: now,
      },
    })

    // Parse preFilledData for the client
    const preFilledData = JSON.parse(updated.preFilledData) as Record<string, unknown>

    return NextResponse.json(
      {
        invitation: {
          id: updated.id,
          familyId: updated.familyId,
          inviterId: updated.inviterId,
          recipientEmail: updated.recipientEmail,
          recipientPhone: updated.recipientPhone,
          recipientName: updated.recipientName,
          status: updated.status,
          role: updated.role,
          channel: updated.channel,
          preFilledData,
          acceptedAt: updated.acceptedAt,
          createdAt: updated.createdAt,
        },
      },
      { status: 200 },
    )
  } catch (error) {
    console.error('[Invitations PATCH] Error:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 },
    )
  }
}
