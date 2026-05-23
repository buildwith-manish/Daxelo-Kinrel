// DAXELO KINREL — WhatsApp Template Management (Admin)
// Pack 04: WhatsApp Platform — API Route

import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'

// ── WhatsApp Business API Configuration ──────────────────────────

const WHATSAPP_API_URL =
  process.env.WHATSAPP_API_URL ?? 'https://graph.facebook.com/v18.0'
const WHATSAPP_ACCESS_TOKEN = process.env.WHATSAPP_ACCESS_TOKEN ?? ''
const WHATSAPP_BUSINESS_ID = process.env.WHATSAPP_BUSINESS_ID ?? ''

// ── GET: List All WhatsApp Templates ─────────────────────────────

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url)
    const status = searchParams.get('status')

    const where: Record<string, unknown> = {}
    if (status) {
      where.status = status
    }

    const templates = await db.whatsAppTemplate.findMany({
      where,
      orderBy: { createdAt: 'desc' },
    })

    // Parse JSON fields for client convenience
    const parsedTemplates = templates.map((t) => ({
      ...t,
      languages: JSON.parse(t.languages) as string[],
      components: JSON.parse(t.components) as Record<string, unknown>,
    }))

    return NextResponse.json({ templates: parsedTemplates }, { status: 200 })
  } catch (error) {
    console.error('[WhatsApp Templates GET] Error:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 },
    )
  }
}

// ── POST: Create a New Template ──────────────────────────────────

interface CreateTemplateBody {
  name: string
  category: 'AUTHENTICATION' | 'UTILITY' | 'MARKETING' | 'SERVICE'
  languages: string[]
  components: Record<string, unknown>
}

export async function POST(request: NextRequest) {
  try {
    const body: CreateTemplateBody = await request.json()
    const { name, category, languages, components } = body

    if (!name || !category || !languages?.length) {
      return NextResponse.json(
        { error: 'name, category, and languages[] are required' },
        { status: 400 },
      )
    }

    const validCategories = ['AUTHENTICATION', 'UTILITY', 'MARKETING', 'SERVICE']
    if (!validCategories.includes(category)) {
      return NextResponse.json(
        { error: `category must be one of: ${validCategories.join(', ')}` },
        { status: 400 },
      )
    }

    // Check for duplicate template name
    const existing = await db.whatsAppTemplate.findUnique({
      where: { name },
    })
    if (existing) {
      return NextResponse.json(
        { error: `Template with name "${name}" already exists` },
        { status: 409 },
      )
    }

    // Submit to WhatsApp Business API
    let whatsappId: string | null = null
    let submissionSucceeded = false

    if (WHATSAPP_ACCESS_TOKEN && WHATSAPP_BUSINESS_ID) {
      try {
        const response = await fetch(
          `${WHATSAPP_API_URL}/${WHATSAPP_BUSINESS_ID}/message_templates`,
          {
            method: 'POST',
            headers: {
              Authorization: `Bearer ${WHATSAPP_ACCESS_TOKEN}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              name,
              category,
              languages: languages.map((lang) => ({ code: lang })),
              components: Array.isArray(components) ? components : [components],
            }),
          },
        )

        if (response.ok) {
          const data = await response.json()
          whatsappId = data.id ?? null
          submissionSucceeded = true
        } else {
          const errorData = await response.json().catch(() => ({}))
          console.error(
            '[WhatsApp Templates POST] WhatsApp API rejected template:',
            JSON.stringify(errorData),
          )
        }
      } catch (apiError) {
        console.error(
          '[WhatsApp Templates POST] WhatsApp API call failed:',
          apiError,
        )
      }
    } else {
      console.warn(
        '[WhatsApp Templates POST] WhatsApp API credentials not configured; creating local record only',
      )
    }

    // Create local record with status='pending' (or 'submitted' if API call succeeded)
    const template = await db.whatsAppTemplate.create({
      data: {
        name,
        category,
        status: submissionSucceeded ? 'pending' : 'pending',
        whatsappId,
        languages: JSON.stringify(languages),
        components: JSON.stringify(components),
      },
    })

    return NextResponse.json(
      {
        template: {
          ...template,
          languages: JSON.parse(template.languages) as string[],
          components: JSON.parse(template.components) as Record<string, unknown>,
        },
      },
      { status: 201 },
    )
  } catch (error) {
    console.error('[WhatsApp Templates POST] Error:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 },
    )
  }
}

// ── PUT: Sync Template Status from WhatsApp ──────────────────────

interface SyncTemplateBody {
  templateId: string
}

export async function PUT(request: NextRequest) {
  try {
    const body: SyncTemplateBody = await request.json()
    const { templateId } = body

    if (!templateId) {
      return NextResponse.json(
        { error: 'templateId is required' },
        { status: 400 },
      )
    }

    const localTemplate = await db.whatsAppTemplate.findUnique({
      where: { id: templateId },
    })

    if (!localTemplate) {
      return NextResponse.json(
        { error: 'Template not found' },
        { status: 404 },
      )
    }

    if (!localTemplate.whatsappId) {
      return NextResponse.json(
        { error: 'Template has not been submitted to WhatsApp yet (no whatsappId)' },
        { status: 400 },
      )
    }

    let remoteStatus: string | null = null
    let remoteRejectionReason: string | null = null

    // Fetch template status from WhatsApp API
    if (WHATSAPP_ACCESS_TOKEN) {
      try {
        const response = await fetch(
          `${WHATSAPP_API_URL}/${localTemplate.whatsappId}`,
          {
            method: 'GET',
            headers: {
              Authorization: `Bearer ${WHATSAPP_ACCESS_TOKEN}`,
            },
          },
        )

        if (response.ok) {
          const data = await response.json()
          remoteStatus = data.status ?? null
          remoteRejectionReason = data.rejected_reason ?? null
        } else {
          const errorData = await response.json().catch(() => ({}))
          console.error(
            '[WhatsApp Templates PUT] Failed to fetch template from WhatsApp:',
            JSON.stringify(errorData),
          )
        }
      } catch (apiError) {
        console.error(
          '[WhatsApp Templates PUT] WhatsApp API call failed:',
          apiError,
        )
      }
    }

    // Update local record
    const now = new Date()
    const updateData: Record<string, unknown> = {
      lastSyncedAt: now,
    }

    if (remoteStatus) {
      updateData.status = remoteStatus
    }
    if (remoteRejectionReason) {
      updateData.rejectionReason = remoteRejectionReason
    }

    const updated = await db.whatsAppTemplate.update({
      where: { id: templateId },
      data: updateData,
    })

    return NextResponse.json(
      {
        template: {
          ...updated,
          languages: JSON.parse(updated.languages) as string[],
          components: JSON.parse(updated.components) as Record<string, unknown>,
        },
      },
      { status: 200 },
    )
  } catch (error) {
    console.error('[WhatsApp Templates PUT] Error:', error)
    return NextResponse.json(
      { error: 'Internal server error' },
      { status: 500 },
    )
  }
}
