// DAXELO KINREL — Pack 08: Moderation Queue Endpoint
// GET — Queue items filtered by status, priority, category (moderator+ only)
// POST — Submit moderator action on queue item

import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { isUserModerator } from '@/lib/moderation/auto-rules'
import { applyAction, assignReviewer } from '@/lib/moderation/moderation-service'

// ── GET: Moderation Queue ───────────────────────────────────────────────

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url)
    const userId = searchParams.get('userId')
    const status = searchParams.get('status') || undefined
    const priority = searchParams.get('priority') || undefined
    const category = searchParams.get('category') || undefined
    const limit = parseInt(searchParams.get('limit') || '50', 10)

    // Auth check: must be moderator
    if (!userId) {
      return NextResponse.json({ error: 'userId is required' }, { status: 400 })
    }

    const isMod = await isUserModerator(userId)
    if (!isMod) {
      return NextResponse.json({ error: 'Access denied. Moderator role required.' }, { status: 403 })
    }

    // Build where clause
    const where: Record<string, unknown> = {}
    if (status) where.status = status
    if (priority) where.priority = priority
    if (category) where.category = category

    // Default to pending items if no status specified
    if (!status) {
      where.status = { in: ['pending', 'under_review'] }
    }

    const cases = await db.moderationCase.findMany({
      where,
      orderBy: [
        { priority: 'desc' },
        { createdAt: 'asc' },
      ],
      take: Math.min(limit, 100),
    })

    // Get counts by status for dashboard
    const statusCounts = await db.moderationCase.groupBy({
      by: ['status'],
      _count: { id: true },
    })

    const queueStats = {
      pending: statusCounts.find(s => s.status === 'pending')?._count.id || 0,
      underReview: statusCounts.find(s => s.status === 'under_review')?._count.id || 0,
      actioned: statusCounts.find(s => s.status === 'actioned')?._count.id || 0,
      escalated: statusCounts.find(s => s.status === 'escalated')?._count.id || 0,
      appealed: statusCounts.find(s => s.status === 'appealed')?._count.id || 0,
    }

    return NextResponse.json({
      cases,
      stats: queueStats,
      total: cases.length,
    })

  } catch (error) {
    console.error('Moderation queue GET error:', error)
    return NextResponse.json({ error: 'Failed to fetch queue' }, { status: 500 })
  }
}

// ── POST: Moderator Action ──────────────────────────────────────────────

export async function POST(request: NextRequest) {
  try {
    const body = await request.json()
    const { caseId, moderatorId, action, notes, contentAction } = body

    // Validation
    if (!caseId || !moderatorId || !action) {
      return NextResponse.json(
        { error: 'Missing required fields: caseId, moderatorId, action' },
        { status: 400 },
      )
    }

    const validActions = ['approve', 'reject', 'restrict', 'escalate']
    if (!validActions.includes(action)) {
      return NextResponse.json(
        { error: `Invalid action. Must be one of: ${validActions.join(', ')}` },
        { status: 400 },
      )
    }

    // Check moderator
    const isMod = await isUserModerator(moderatorId)
    if (!isMod) {
      return NextResponse.json({ error: 'Access denied. Moderator role required.' }, { status: 403 })
    }

    // Check case exists
    const modCase = await db.moderationCase.findUnique({ where: { id: caseId } })
    if (!modCase) {
      return NextResponse.json({ error: 'Case not found' }, { status: 404 })
    }

    // Map action to content action
    const actionMap: Record<string, string> = {
      approve: 'none',
      reject: contentAction || 'removed',
      restrict: 'hidden',
      escalate: modCase.contentAction || 'hidden',
    }

    // Apply the action
    await applyAction(caseId, actionMap[action], moderatorId)

    // If escalating, set priority to urgent
    if (action === 'escalate') {
      await db.moderationCase.update({
        where: { id: caseId },
        data: {
          status: 'escalated',
          priority: 'urgent',
          reviewNotes: notes || null,
        },
      })
    }

    // Update with review notes
    if (notes) {
      await db.moderationCase.update({
        where: { id: caseId },
        data: { reviewNotes: notes },
      })
    }

    // Log the moderation action
    await db.moderationAction.create({
      data: {
        moderatorId,
        targetType: modCase.contentType,
        targetId: modCase.contentId,
        action: action === 'approve' ? 'pin' : action === 'reject' ? 'delete' : action === 'restrict' ? 'hide' : 'lock',
        reason: notes || `Moderator action: ${action}`,
      },
    })

    return NextResponse.json({
      caseId,
      action,
      message: `Case ${caseId} has been ${action === 'approve' ? 'approved' : action === 'reject' ? 'rejected' : action === 'restrict' ? 'restricted' : 'escalated'}.`,
    })

  } catch (error) {
    console.error('Moderation queue POST error:', error)
    return NextResponse.json({ error: 'Failed to process moderator action' }, { status: 500 })
  }
}
