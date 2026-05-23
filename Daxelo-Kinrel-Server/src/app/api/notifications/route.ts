// DAXELO KINREL — Notifications API
// Pack 04: WhatsApp Platform — API Route

import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { notificationEngine } from '@/lib/notifications/engine'
import { type NotificationEvent, type NotificationEventType, type NotificationPriority } from '@/lib/notifications/event-schema'

// ── GET: Get User's Notifications ────────────────────────────────

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url)
    const userId = searchParams.get('userId')
    const readFilter = searchParams.get('read')
    const limit = parseInt(searchParams.get('limit') ?? '20')
    const offset = parseInt(searchParams.get('offset') ?? '0')

    if (!userId) {
      return NextResponse.json(
        { error: 'userId query parameter is required' },
        { status: 400 },
      )
    }

    const where: Record<string, unknown> = { userId }

    if (readFilter !== null && readFilter !== undefined && readFilter !== '') {
      where.read = readFilter === 'true'
    }

    const [notifications, unreadCount] = await Promise.all([
      db.notification.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        take: Math.min(limit, 100),
        skip: offset,
        include: {
          updates: {
            orderBy: { createdAt: 'desc' },
          },
        },
      }),
      db.notification.count({
        where: { userId, read: false },
      }),
    ])

    // Parse JSON channels for client convenience
    const parsedNotifications = notifications.map((n) => ({
      ...n,
      channels: JSON.parse(n.channels) as string[],
    }))

    return NextResponse.json(
      {
        notifications: parsedNotifications,
        unreadCount,
        limit,
        offset,
      },
      { status: 200 },
    )
  } catch (error) {
    console.error('[Notifications GET] Error:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 },
    )
  }
}

// ── PATCH: Mark Notifications as Read ────────────────────────────

interface MarkReadBody {
  userId: string
  notificationIds?: string[]
}

export async function PATCH(request: NextRequest) {
  try {
    const body: MarkReadBody = await request.json()
    const { userId, notificationIds } = body

    if (!userId) {
      return NextResponse.json(
        { error: 'userId is required' },
        { status: 400 },
      )
    }

    const now = new Date()

    let count: number

    if (notificationIds && notificationIds.length > 0) {
      // Mark specific notifications as read
      const result = await db.notification.updateMany({
        where: {
          id: { in: notificationIds },
          userId,
          read: false,
        },
        data: {
          read: true,
          readAt: now,
        },
      })
      count = result.count
    } else {
      // Mark all as read for this user
      const result = await db.notification.updateMany({
        where: {
          userId,
          read: false,
        },
        data: {
          read: true,
          readAt: now,
        },
      })
      count = result.count
    }

    return NextResponse.json({ updated: count }, { status: 200 })
  } catch (error) {
    console.error('[Notifications PATCH] Error:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 },
    )
  }
}

// ── PUT: Update Notification Preferences ─────────────────────────

interface UpdatePreferencesBody {
  userId: string
  eventType: string
  whatsapp?: boolean
  push?: boolean
  inApp?: boolean
  email?: boolean
  quietHoursStart?: string
  quietHoursEnd?: string
  digestMode?: 'immediate' | 'hourly' | 'daily'
  maxPerDay?: number
}

export async function PUT(request: NextRequest) {
  try {
    const body: UpdatePreferencesBody = await request.json()
    const {
      userId,
      eventType,
      whatsapp,
      push,
      inApp,
      email,
      quietHoursStart,
      quietHoursEnd,
      digestMode,
      maxPerDay,
    } = body

    if (!userId || !eventType) {
      return NextResponse.json(
        { error: 'userId and eventType are required' },
        { status: 400 },
      )
    }

    // Verify user exists
    const user = await db.user.findUnique({ where: { id: userId } })
    if (!user) {
      return NextResponse.json(
        { error: 'User not found' },
        { status: 404 },
      )
    }

    // Upsert notification preference
    const preference = await db.notificationPreference.upsert({
      where: {
        userId_eventType: {
          userId,
          eventType,
        },
      },
      update: {
        ...(whatsapp !== undefined ? { whatsapp } : {}),
        ...(push !== undefined ? { push } : {}),
        ...(inApp !== undefined ? { inApp } : {}),
        ...(email !== undefined ? { email } : {}),
        ...(quietHoursStart !== undefined ? { quietHoursStart } : {}),
        ...(quietHoursEnd !== undefined ? { quietHoursEnd } : {}),
        ...(digestMode !== undefined ? { digestMode } : {}),
        ...(maxPerDay !== undefined ? { maxPerDay } : {}),
      },
      create: {
        userId,
        eventType,
        whatsapp: whatsapp ?? true,
        push: push ?? true,
        inApp: inApp ?? true,
        email: email ?? false,
        quietHoursStart: quietHoursStart ?? null,
        quietHoursEnd: quietHoursEnd ?? null,
        digestMode: digestMode ?? 'immediate',
        maxPerDay: maxPerDay ?? 10,
      },
    })

    return NextResponse.json({ preference }, { status: 200 })
  } catch (error) {
    console.error('[Notifications PUT] Error:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 },
    )
  }
}

// ── POST: Create and Send a Notification ─────────────────────────

interface CreateNotificationBody {
  type: NotificationEventType
  actorUserId: string
  targetUserId: string
  familyId?: string
  personId?: string
  payload: Record<string, unknown>
  priority: NotificationPriority
}

export async function POST(request: NextRequest) {
  try {
    const body: CreateNotificationBody = await request.json()
    const { type, actorUserId, targetUserId, familyId, personId, payload, priority } = body

    if (!type || !actorUserId || !targetUserId || !payload || !priority) {
      return NextResponse.json(
        { error: 'type, actorUserId, targetUserId, payload, and priority are required' },
        { status: 400 },
      )
    }

    const validPriorities = ['critical', 'high', 'normal', 'low']
    if (!validPriorities.includes(priority)) {
      return NextResponse.json(
        { error: `priority must be one of: ${validPriorities.join(', ')}` },
        { status: 400 },
      )
    }

    // Build the notification event with all required fields
    const now = new Date()
    const dedupKey = `${type}:${targetUserId}:${familyId ?? ''}:${personId ?? ''}:${now.getTime()}`

    const event: NotificationEvent = {
      id: crypto.randomUUID(),
      type,
      actorUserId,
      targetUserId,
      familyId,
      personId,
      payload,
      priority,
      createdAt: now,
      dedupKey,
    }

    // Process through notification engine
    const result = await notificationEngine.process(event)

    return NextResponse.json(
      { notification: result },
      { status: 201 },
    )
  } catch (error) {
    console.error('[Notifications POST] Error:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 },
    )
  }
}
