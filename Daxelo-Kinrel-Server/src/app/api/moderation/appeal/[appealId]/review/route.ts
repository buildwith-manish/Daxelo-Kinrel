// DAXELO KINREL — Pack 08: Appeal Review Endpoint
// POST — Review an appeal (different moderator for tier 2)

import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ appealId: string }> },
) {
  try {
    const { appealId } = await params
    const body = await request.json()
    const { reviewerId, decision, notes } = body

    // Validation
    if (!reviewerId || !decision) {
      return NextResponse.json(
        { error: 'Missing required fields: reviewerId, decision' },
        { status: 400 },
      )
    }

    const validDecisions = ['upheld', 'reinstated', 'reduced', 'dismissed']
    if (!validDecisions.includes(decision)) {
      return NextResponse.json(
        { error: `Invalid decision. Must be one of: ${validDecisions.join(', ')}` },
        { status: 400 },
      )
    }

    // Check appeal exists
    const appeal = await db.moderationAppeal.findUnique({
      where: { id: appealId },
    })

    if (!appeal) {
      return NextResponse.json({ error: 'Appeal not found' }, { status: 404 })
    }

    if (appeal.status !== 'pending' && appeal.status !== 'under_review') {
      return NextResponse.json(
        { error: `Appeal is already ${appeal.status}` },
        { status: 400 },
      )
    }

    // For tier 2 appeals, ensure a different moderator reviews
    if (appeal.appealTier === 2 && appeal.reviewerId === reviewerId) {
      return NextResponse.json(
        { error: 'Tier 2 appeal must be reviewed by a different moderator than tier 1' },
        { status: 403 },
      )
    }

    // Check reviewer is a moderator
    const reviewer = await db.user.findUnique({ where: { id: reviewerId } })
    if (!reviewer || (reviewer.role !== 'admin' && reviewer.role !== 'agent')) {
      return NextResponse.json(
        { error: 'Only moderators can review appeals' },
        { status: 403 },
      )
    }

    // Update the appeal
    await db.moderationAppeal.update({
      where: { id: appealId },
      data: {
        status: decision === 'upheld' ? 'upheld' : decision,
        reviewerId,
        reviewedAt: new Date(),
        reviewDecision: decision,
        reviewNotes: notes || null,
      },
    })

    // Update the moderation case based on decision
    const caseId = appeal.caseId
    if (decision === 'reinstated' || decision === 'dismissed') {
      // Restore the content
      await db.moderationCase.update({
        where: { id: caseId },
        data: {
          status: 'dismissed',
          contentAction: 'none',
          reviewDecision: decision,
          reviewNotes: notes || null,
        },
      })
    } else if (decision === 'reduced') {
      // Reduce the action (e.g., from 'removed' to 'hidden')
      const modCase = await db.moderationCase.findUnique({ where: { id: caseId } })
      await db.moderationCase.update({
        where: { id: caseId },
        data: {
          contentAction: modCase?.contentAction === 'removed' ? 'hidden' : 'none',
          reviewDecision: 'reduced',
          reviewNotes: notes || null,
        },
      })
    } else {
      // Upheld — keep the current action
      await db.moderationCase.update({
        where: { id: caseId },
        data: {
          status: 'actioned',
          reviewDecision: 'uphold',
          reviewNotes: notes || null,
        },
      })
    }

    // Log the action
    await db.moderationActionItem.create({
      data: {
        caseId,
        actionType: 'appeal_reviewed',
        actorId: reviewerId,
        details: JSON.stringify({
          appealId,
          decision,
          tier: appeal.appealTier,
          timestamp: new Date().toISOString(),
        }),
      },
    })

    // Write audit log
    await db.moderationAuditLog.create({
      data: {
        action: 'appeal',
        contentType: 'mixed',
        contentId: caseId,
        actorType: 'human_moderator',
        actorId: reviewerId,
        result: decision,
        reason: notes || `Appeal ${decision}`,
        metadata: JSON.stringify({ appealId, tier: appeal.appealTier }),
      },
    })

    return NextResponse.json({
      appealId,
      decision,
      message: `Appeal has been ${decision}. ${decision === 'upheld' ? 'The original action stands.' : decision === 'reinstated' ? 'Content has been restored.' : decision === 'reduced' ? 'The action has been reduced.' : 'The case has been dismissed.'}`,
    })

  } catch (error) {
    console.error('Appeal review error:', error)
    return NextResponse.json(
      { error: 'Failed to review appeal' },
      { status: 500 },
    )
  }
}
