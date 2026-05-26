// DAXELO KINREL — Shareable Link API
// Pack 04: WhatsApp Platform — API Route
//
// POST /api/share — Create a new shareable link
// GET  /api/share — Get share stats for a given token

import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { z } from 'zod'
import { trackInviteEvent } from '@/lib/invitations/conversion-tracking'
import { generateShareCardUrl } from '@/lib/invitations/deep-link'

// ── POST: Create Shareable Link ────────────────────────────────────────

const createShareableLinkSchema = z.object({
  cardType: z.enum([
    'family_tree',
    'birthday',
    'anniversary',
    'memorial',
    'milestone',
    'relationship_discovery',
    'festival_greeting',
  ]),
  familyId: z.string().optional(),
  personId: z.string().optional(),
  title: z.string().min(1).max(200),
  description: z.string().min(1).max(500),
  deepLinkUrl: z.string().url(),
  expiresAt: z.string().datetime().optional(),
})

export async function POST(request: NextRequest) {
  try {
    const userId = request.headers.get('X-User-Id')
    if (!userId) {
      return NextResponse.json(
        { error: 'Unauthorized — X-User-Id header required' },
        { status: 401 }
      )
    }

    const body = await request.json()
    const parsed = createShareableLinkSchema.safeParse(body)
    if (!parsed.success) {
      return NextResponse.json(
        { error: parsed.error.flatten() },
        { status: 400 }
      )
    }

    const data = parsed.data

    // Generate a unique token for the shareable link
    const token = crypto.randomUUID()

    // Parse optional expiration date
    const expiresAt = data.expiresAt ? new Date(data.expiresAt) : null

    // Create the shareable link record
    const shareableLink = await db.shareableLink.create({
      data: {
        token,
        cardType: data.cardType,
        familyId: data.familyId ?? null,
        personId: data.personId ?? null,
        title: data.title,
        description: data.description,
        deepLinkUrl: data.deepLinkUrl,
        expiresAt,
      },
    })

    // Generate the share card URL for OG previews
    const shareUrl = generateShareCardUrl(token)

    // Track the share event
    await trackInviteEvent({
      event: 'invite:whatsapp_share',
      userId,
      familyId: data.familyId,
      metadata: {
        shareToken: token,
        cardType: data.cardType,
        personId: data.personId,
      },
    }).catch((err) => {
      console.error('[Share POST] Failed to track share event:', err)
    })

    return NextResponse.json(
      {
        shareableLink: {
          id: shareableLink.id,
          token: shareableLink.token,
          cardType: shareableLink.cardType,
          familyId: shareableLink.familyId,
          personId: shareableLink.personId,
          title: shareableLink.title,
          description: shareableLink.description,
          deepLinkUrl: shareableLink.deepLinkUrl,
          expiresAt: shareableLink.expiresAt,
          viewCount: shareableLink.viewCount,
          shareCount: shareableLink.shareCount,
          createdAt: shareableLink.createdAt,
        },
        shareUrl,
      },
      { status: 201 }
    )
  } catch (error) {
    console.error('[Share POST] Error:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}

// ── GET: Retrieve Share Stats ──────────────────────────────────────────

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url)
    const token = searchParams.get('token')

    if (!token) {
      return NextResponse.json(
        { error: 'Missing required query parameter: token' },
        { status: 400 }
      )
    }

    const shareableLink = await db.shareableLink.findUnique({
      where: { token },
      select: {
        id: true,
        token: true,
        cardType: true,
        title: true,
        viewCount: true,
        shareCount: true,
        expiresAt: true,
        createdAt: true,
      },
    })

    if (!shareableLink) {
      return NextResponse.json(
        { error: 'Shareable link not found' },
        { status: 404 }
      )
    }

    // Check if link has expired
    const isExpired =
      shareableLink.expiresAt !== null && shareableLink.expiresAt < new Date()

    return NextResponse.json({
      stats: {
        token: shareableLink.token,
        cardType: shareableLink.cardType,
        title: shareableLink.title,
        viewCount: shareableLink.viewCount,
        shareCount: shareableLink.shareCount,
        isExpired,
        createdAt: shareableLink.createdAt,
        expiresAt: shareableLink.expiresAt,
      },
    })
  } catch (error) {
    console.error('[Share GET] Error:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 }
    )
  }
}
