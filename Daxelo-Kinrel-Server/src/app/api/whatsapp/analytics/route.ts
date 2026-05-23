// DAXELO KINREL — WhatsApp Analytics
// Pack 04: WhatsApp Platform — API Route
// v2

import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'

// ── GET: Get WhatsApp Analytics ──────────────────────────────────

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url)
    const event = searchParams.get('event')
    const userId = searchParams.get('userId')
    const templateId = searchParams.get('templateId')
    const startDate = searchParams.get('startDate')
    const endDate = searchParams.get('endDate')
    const limit = parseInt(searchParams.get('limit') ?? '100')

    // Build where clause from query params
    const where: Record<string, unknown> = {}

    if (event) {
      where.event = event
    }
    if (userId) {
      where.userId = userId
    }
    if (templateId) {
      where.templateId = templateId
    }
    if (startDate || endDate) {
      const createdAt: Record<string, Date> = {}
      if (startDate) {
        createdAt.gte = new Date(startDate)
      }
      if (endDate) {
        createdAt.lte = new Date(endDate)
      }
      where.createdAt = createdAt
    }

    const events = await db.whatsAppAnalytics.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      take: Math.min(limit, 1000),
    })

    // Parse JSON metadata for client convenience
    const parsedEvents = events.map((e) => ({
      ...e,
      metadata: JSON.parse(e.metadata) as Record<string, unknown>,
    }))

    return NextResponse.json(
      { events: parsedEvents, count: parsedEvents.length },
      { status: 200 },
    )
  } catch (error) {
    console.error('[WhatsApp Analytics GET] Error:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 },
    )
  }
}

// ── POST: Track a New Analytics Event ────────────────────────────

interface TrackEventBody {
  event: string
  userId?: string
  familyId?: string
  messageId?: string
  templateId?: string
  metadata?: Record<string, unknown>
}

export async function POST(request: NextRequest) {
  try {
    const body: TrackEventBody = await request.json()
    const { event, userId, familyId, messageId, templateId, metadata } = body

    if (!event) {
      return NextResponse.json(
        { error: 'event is required' },
        { status: 400 },
      )
    }

    const analyticsEvent = await db.whatsAppAnalytics.create({
      data: {
        event,
        userId: userId ?? null,
        familyId: familyId ?? null,
        messageId: messageId ?? null,
        templateId: templateId ?? null,
        metadata: JSON.stringify(metadata ?? {}),
      },
    })

    return NextResponse.json(
      {
        event: {
          ...analyticsEvent,
          metadata: JSON.parse(analyticsEvent.metadata) as Record<string, unknown>,
        },
      },
      { status: 201 },
    )
  } catch (error) {
    console.error('[WhatsApp Analytics POST] Error:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 },
    )
  }
}
