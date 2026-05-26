// DAXELO KINREL — Pack 08: Appeals Endpoint
// POST — File an appeal
// POST /[appealId]/review — Review an appeal

import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'

// ── Constants ───────────────────────────────────────────────────────────

const MIN_APPEAL_LENGTH = 10
const MAX_APPEAL_LENGTH = 2000
const APPEAL_WINDOW_HOURS = 48
const MAX_APPEALS_PER_CASE = 2

// ── POST: File an Appeal ────────────────────────────────────────────────

export async function POST(request: NextRequest) {
  try {
    const body = await request.json()
    const { caseId, appellantId, appealReason } = body

    // Validation
    if (!caseId || !appellantId || !appealReason) {
      return NextResponse.json(
        { error: 'Missing required fields: caseId, appellantId, appealReason' },
        { status: 400 },
      )
    }

    if (appealReason.length < MIN_APPEAL_LENGTH) {
      return NextResponse.json(
        { error: `Appeal reason must be at least ${MIN_APPEAL_LENGTH} characters` },
        { status: 400 },
      )
    }

    if (appealReason.length > MAX_APPEAL_LENGTH) {
      return NextResponse.json(
        { error: `Appeal reason must be at most ${MAX_APPEAL_LENGTH} characters` },
        { status: 400 },
      )
    }

    // Check case exists
    const modCase = await db.moderationCase.findUnique({
      where: { id: caseId },
    })

    if (!modCase) {
      return NextResponse.json({ error: 'Moderation case not found' }, { status: 404 })
    }

    // Check appellant is the content author
    if (modCase.authorId !== appellantId) {
      return NextResponse.json(
        { error: 'Only the content author can file an appeal' },
        { status: 403 },
      )
    }

    // Check 48-hour window
    const caseCreated = modCase.createdAt
    const now = new Date()
    const hoursSinceCase = (now.getTime() - caseCreated.getTime()) / (1000 * 60 * 60)

    if (hoursSinceCase > APPEAL_WINDOW_HOURS) {
      return NextResponse.json(
        { error: `Appeals must be filed within ${APPEAL_WINDOW_HOURS} hours of the action` },
        { status: 400 },
      )
    }

    // Check max appeals per case
    const existingAppeals = await db.moderationAppeal.count({
      where: { caseId },
    })

    if (existingAppeals >= MAX_APPEALS_PER_CASE) {
      return NextResponse.json(
        { error: `Maximum ${MAX_APPEALS_PER_CASE} appeals allowed per case` },
        { status: 400 },
      )
    }

    // Determine appeal tier
    const currentTier = existingAppeals + 1

    if (currentTier > 2) {
      return NextResponse.json(
        { error: 'Maximum appeal tiers exhausted' },
        { status: 400 },
      )
    }

    // Create the appeal
    const appeal = await db.moderationAppeal.create({
      data: {
        caseId,
        appellantId,
        appealReason,
        appealTier: currentTier,
        status: 'pending',
      },
    })

    // Update case status
    await db.moderationCase.update({
      where: { id: caseId },
      data: { status: 'appealed' },
    })

    // Log the appeal
    await db.moderationActionItem.create({
      data: {
        caseId,
        actionType: 'appealed',
        actorId: appellantId,
        details: JSON.stringify({
          appealId: appeal.id,
          tier: currentTier,
          timestamp: new Date().toISOString(),
        }),
      },
    })

    // Write audit log
    await db.moderationAuditLog.create({
      data: {
        action: 'appeal',
        contentType: modCase.contentType,
        contentId: modCase.contentId,
        actorType: 'system',
        actorId: appellantId,
        result: 'appeal_filed',
        reason: appealReason.substring(0, 500),
        metadata: JSON.stringify({ appealId: appeal.id, tier: currentTier }),
      },
    })

    return NextResponse.json({
      id: appeal.id,
      caseId,
      tier: currentTier,
      status: appeal.status,
      message: currentTier === 1
        ? 'Your appeal has been filed. A moderator will review it within 48 hours.'
        : 'Your tier 2 appeal has been filed. A different moderator will review it within 24 hours.',
    }, { status: 201 })

  } catch (error) {
    console.error('Appeal filing error:', error)
    return NextResponse.json(
      { error: 'Failed to file appeal' },
      { status: 500 },
    )
  }
}
