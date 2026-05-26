// DAXELO KINREL — WhatsApp Consent Management
// Pack 04: WhatsApp Platform — API Route

import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'

// ── GET: Get Current User's WhatsApp Consent Status ──────────────

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url)
    const userId = searchParams.get('userId')

    if (!userId) {
      return NextResponse.json(
        { error: 'userId query parameter is required' },
        { status: 400 },
      )
    }

    const consent = await db.whatsAppConsent.findUnique({
      where: { userId },
    })

    if (!consent) {
      return NextResponse.json(
        { consent: null, message: 'No WhatsApp consent record found for this user' },
        { status: 200 },
      )
    }

    // Parse JSON fields for client convenience
    const parsedConsent = {
      ...consent,
      messageCategories: JSON.parse(consent.messageCategories) as string[],
    }

    return NextResponse.json({ consent: parsedConsent }, { status: 200 })
  } catch (error) {
    console.error('[WhatsApp Consent GET] Error:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 },
    )
  }
}

// ── POST: Opt-in to WhatsApp Notifications ───────────────────────

interface OptInBody {
  userId: string
  phone: string
  optInMethod: 'app_settings' | 'onboarding' | 'invite_flow' | 'customer_service'
  categories: string[]
  marketingConsent: boolean
}

export async function POST(request: NextRequest) {
  try {
    const body: OptInBody = await request.json()
    const { userId, phone, optInMethod, categories, marketingConsent } = body

    if (!userId || !phone || !optInMethod) {
      return NextResponse.json(
        { error: 'userId, phone, and optInMethod are required' },
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

    const now = new Date()

    // Create or update WhatsAppConsent record
    const consent = await db.whatsAppConsent.upsert({
      where: { userId },
      update: {
        phone,
        optedIn: true,
        optInMethod,
        optInAt: now,
        optOutAt: null,
        optOutMethod: null,
        optOutReason: null,
        messageCategories: JSON.stringify(categories),
        marketingConsent: marketingConsent ?? false,
        marketingOptInAt: marketingConsent ? now : undefined,
        consentVersion: 'v1',
      },
      create: {
        userId,
        phone,
        optedIn: true,
        optInMethod,
        optInAt: now,
        messageCategories: JSON.stringify(categories),
        marketingConsent: marketingConsent ?? false,
        marketingOptInAt: marketingConsent ? now : undefined,
        consentVersion: 'v1',
      },
    })

    // Create WhatsAppOptIn records for each category
    for (const category of categories) {
      await db.whatsAppOptIn.upsert({
        where: {
          phone_templateType: {
            phone,
            templateType: category,
          },
        },
        update: {
          optedIn: true,
          optedInAt: now,
        },
        create: {
          phone,
          templateType: category,
          optedIn: true,
          optedInAt: now,
        },
      })
    }

    // Log analytics event
    await db.whatsAppAnalytics.create({
      data: {
        event: 'whatsapp.opt_in.completed',
        userId,
        metadata: JSON.stringify({
          source: optInMethod,
          categories,
          marketingConsent,
        }),
      },
    })

    // Parse JSON fields for response
    const parsedConsent = {
      ...consent,
      messageCategories: JSON.parse(consent.messageCategories) as string[],
    }

    return NextResponse.json({ consent: parsedConsent }, { status: 200 })
  } catch (error) {
    console.error('[WhatsApp Consent POST] Error:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 },
    )
  }
}

// ── PUT: Opt-out of WhatsApp Notifications ───────────────────────

interface OptOutBody {
  userId: string
  optOutMethod: 'whatsapp_stop' | 'app_settings' | 'account_deletion'
  reason?: string
}

export async function PUT(request: NextRequest) {
  try {
    const body: OptOutBody = await request.json()
    const { userId, optOutMethod, reason } = body

    if (!userId || !optOutMethod) {
      return NextResponse.json(
        { error: 'userId and optOutMethod are required' },
        { status: 400 },
      )
    }

    const existing = await db.whatsAppConsent.findUnique({
      where: { userId },
    })

    if (!existing) {
      return NextResponse.json(
        { error: 'No WhatsApp consent record found for this user' },
        { status: 404 },
      )
    }

    const now = new Date()

    // Update WhatsAppConsent: optedIn=false, optOutAt=now, marketingConsent=false
    const updated = await db.whatsAppConsent.update({
      where: { userId },
      data: {
        optedIn: false,
        optOutAt: now,
        optOutMethod,
        optOutReason: reason ?? null,
        marketingConsent: false,
        marketingOptInAt: null,
        messageCategories: JSON.stringify([]),
      },
    })

    // Delete WhatsAppOptIn records for this phone
    await db.whatsAppOptIn.deleteMany({
      where: { phone: existing.phone },
    })

    // Log analytics event
    await db.whatsAppAnalytics.create({
      data: {
        event: 'whatsapp.opt_out.requested',
        userId,
        metadata: JSON.stringify({
          method: optOutMethod,
          reason: reason ?? null,
        }),
      },
    })

    const parsedConsent = {
      ...updated,
      messageCategories: JSON.parse(updated.messageCategories) as string[],
    }

    return NextResponse.json({ consent: parsedConsent }, { status: 200 })
  } catch (error) {
    console.error('[WhatsApp Consent PUT] Error:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 },
    )
  }
}

// ── PATCH: Update Marketing Consent ──────────────────────────────

interface UpdateMarketingBody {
  userId: string
  marketingConsent: boolean
  method: string
}

export async function PATCH(request: NextRequest) {
  try {
    const body: UpdateMarketingBody = await request.json()
    const { userId, marketingConsent, method } = body

    if (!userId || typeof marketingConsent !== 'boolean') {
      return NextResponse.json(
        { error: 'userId and marketingConsent (boolean) are required' },
        { status: 400 },
      )
    }

    const existing = await db.whatsAppConsent.findUnique({
      where: { userId },
    })

    if (!existing) {
      return NextResponse.json(
        { error: 'No WhatsApp consent record found for this user' },
        { status: 404 },
      )
    }

    const now = new Date()

    // Update marketing consent; if enabling, set marketingOptInAt
    const updated = await db.whatsAppConsent.update({
      where: { userId },
      data: {
        marketingConsent,
        marketingOptInAt: marketingConsent ? now : null,
      },
    })

    // If enabling marketing consent, ensure the marketing opt-in category exists
    if (marketingConsent) {
      await db.whatsAppOptIn.upsert({
        where: {
          phone_templateType: {
            phone: existing.phone,
            templateType: 'marketing',
          },
        },
        update: {
          optedIn: true,
          optedInAt: now,
        },
        create: {
          phone: existing.phone,
          templateType: 'marketing',
          optedIn: true,
          optedInAt: now,
        },
      })
    } else {
      // Remove marketing opt-in category
      await db.whatsAppOptIn.deleteMany({
        where: {
          phone: existing.phone,
          templateType: 'marketing',
        },
      })
    }

    const parsedConsent = {
      ...updated,
      messageCategories: JSON.parse(updated.messageCategories) as string[],
    }

    return NextResponse.json({ consent: parsedConsent }, { status: 200 })
  } catch (error) {
    console.error('[WhatsApp Consent PATCH] Error:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 },
    )
  }
}
