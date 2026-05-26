// DAXELO KINREL — Pack 10: Content Classification API
// POST /api/moderation/classify

import { NextRequest, NextResponse } from 'next/server'
import { getServerSession } from 'next-auth'
import { authOptions } from '@/lib/auth'
import { z } from 'zod'

const classifySchema = z.object({
  contentType: z.string().min(1),
  content: z.string().min(1),
  contentId: z.string().optional(),
})

export async function POST(request: NextRequest) {
  const session = await getServerSession(authOptions)
  if (!session?.user?.id) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const body = await request.json().catch(() => null)
  if (!body) {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 422 })
  }

  const parsed = classifySchema.safeParse(body)
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

  const { contentType, content, contentId } = parsed.data

  // Try to use the moderation service if available
  try {
    const { moderateContent } = await import('@/lib/moderation/moderation-service')
    const result = await moderateContent({
      contentType,
      contentId: contentId || 'classify-request',
      content,
      authorId: session.user.id,
      source: 'auto',
    })

    return NextResponse.json({
      category: result.category,
      confidence: result.confidence,
      autoAction: result.autoAction,
      flaggedCategories: result.flaggedCategories,
      details: result.details,
    })
  } catch {
    // Fallback stub classification if moderation service fails
    const stubResult = performStubClassification(contentType, content)

    return NextResponse.json(stubResult)
  }
}

// ── Stub Classification Logic ────────────────────────────────────────

function performStubClassification(contentType: string, content: string): {
  category: string
  confidence: number
  autoAction: string
} {
  // Basic keyword-based stub classification
  const lowerContent = content.toLowerCase()

  // High-risk patterns
  const highRiskPatterns = [
    'violence', 'kill', 'threat', 'weapon', 'bomb',
    'nude', 'sexual', 'porn',
  ]

  const mediumRiskPatterns = [
    'hate', 'abuse', 'harass', 'stupid', 'idiot',
    'caste', 'untouchable',
  ]

  const piiPatterns = [
    'aadhaar', 'pan card', 'social security', 'credit card',
    'bank account', 'password', 'pin number',
  ]

  for (const pattern of highRiskPatterns) {
    if (lowerContent.includes(pattern)) {
      return {
        category: 'violence',
        confidence: 0.85,
        autoAction: 'quarantine',
      }
    }
  }

  for (const pattern of mediumRiskPatterns) {
    if (lowerContent.includes(pattern)) {
      return {
        category: 'harassment',
        confidence: 0.7,
        autoAction: 'allow_with_flag',
      }
    }
  }

  for (const pattern of piiPatterns) {
    if (lowerContent.includes(pattern)) {
      return {
        category: 'pii_exposure',
        confidence: 0.75,
        autoAction: 'allow_with_flag',
      }
    }
  }

  // Default: safe
  return {
    category: 'safe',
    confidence: 0.95,
    autoAction: 'allow',
  }
}
