// DAXELO KINREL — Pack 08: Moderation Statistics Dashboard
// GET — Dashboard stats (pending count, resolved today, avg resolution time, CSAM count, appeal stats)

import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { isUserModerator } from '@/lib/moderation/auto-rules'

// ── GET: Moderation Stats ───────────────────────────────────────────────

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url)
    const userId = searchParams.get('userId')

    // Auth check
    if (!userId) {
      return NextResponse.json({ error: 'userId is required' }, { status: 400 })
    }

    const isMod = await isUserModerator(userId)
    if (!isMod) {
      return NextResponse.json({ error: 'Access denied. Moderator role required.' }, { status: 403 })
    }

    const now = new Date()
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate())
    const last7Days = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000)
    const last30Days = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000)

    // ── Pending cases count ──
    const pendingCount = await db.moderationCase.count({
      where: { status: { in: ['pending', 'under_review'] } },
    })

    // ── Resolved today ──
    const resolvedToday = await db.moderationCase.count({
      where: {
        status: { in: ['actioned', 'dismissed'] },
        reviewedAt: { gte: todayStart },
      },
    })

    // ── Average resolution time ──
    const resolvedCases = await db.moderationCase.findMany({
      where: {
        status: { in: ['actioned', 'dismissed'] },
        reviewedAt: { not: null },
        createdAt: { gte: last7Days },
      },
      select: {
        createdAt: true,
        reviewedAt: true,
      },
    })

    const resolutionTimes = resolvedCases
      .filter(c => c.reviewedAt)
      .map(c => (c.reviewedAt!.getTime() - c.createdAt.getTime()) / (1000 * 60 * 60))

    const avgResolutionHours = resolutionTimes.length > 0
      ? Math.round((resolutionTimes.reduce((a, b) => a + b, 0) / resolutionTimes.length) * 10) / 10
      : 0

    // ── CSAM count ──
    const csamCount = await db.moderationCase.count({
      where: {
        category: 'csam',
        createdAt: { gte: last30Days },
      },
    })

    const csamPending = await db.moderationCase.count({
      where: {
        category: 'csam',
        status: { in: ['pending', 'escalated'] },
      },
    })

    // ── Appeal stats ──
    const totalAppeals = await db.moderationAppeal.count({
      where: { createdAt: { gte: last30Days } },
    })

    const pendingAppeals = await db.moderationAppeal.count({
      where: { status: { in: ['pending', 'under_review'] } },
    })

    const resolvedAppeals = await db.moderationAppeal.count({
      where: {
        status: { in: ['upheld', 'reinstated', 'reduced', 'dismissed'] },
        createdAt: { gte: last30Days },
      },
    })

    const appealResolutionRate = totalAppeals > 0
      ? Math.round((resolvedAppeals / totalAppeals) * 100)
      : 0

    // ── Cases by category (last 30 days) ──
    const categoryBreakdown = await db.moderationCase.groupBy({
      by: ['category'],
      _count: { id: true },
      where: { createdAt: { gte: last30Days } },
    })

    // ── Cases by priority ──
    const priorityBreakdown = await db.moderationCase.groupBy({
      by: ['priority'],
      _count: { id: true },
      where: { status: { in: ['pending', 'under_review'] } },
    })

    // ── Cases by source (last 30 days) ──
    const sourceBreakdown = await db.moderationCase.groupBy({
      by: ['source'],
      _count: { id: true },
      where: { createdAt: { gte: last30Days } },
    })

    // ── Content reports pending ──
    const pendingReports = await db.contentReport.count({
      where: { status: 'pending' },
    })

    // ── User moderation statuses ──
    const userStatusBreakdown = await db.userModerationStatus.groupBy({
      by: ['status'],
      _count: { id: true },
    })

    // ── Daily trend (last 7 days) ──
    const dailyTrend: Array<{ date: string; created: number; resolved: number }> = []
    for (let i = 6; i >= 0; i--) {
      const dayStart = new Date(now.getTime() - i * 24 * 60 * 60 * 1000)
      dayStart.setHours(0, 0, 0, 0)
      const dayEnd = new Date(dayStart.getTime() + 24 * 60 * 60 * 1000)

      const created = await db.moderationCase.count({
        where: { createdAt: { gte: dayStart, lt: dayEnd } },
      })

      const resolved = await db.moderationCase.count({
        where: {
          reviewedAt: { gte: dayStart, lt: dayEnd },
          status: { in: ['actioned', 'dismissed'] },
        },
      })

      dailyTrend.push({
        date: dayStart.toISOString().split('T')[0],
        created,
        resolved,
      })
    }

    return NextResponse.json({
      overview: {
        pendingCount,
        resolvedToday,
        avgResolutionHours,
        csamCount,
        csamPending,
        pendingReports,
      },
      appeals: {
        total: totalAppeals,
        pending: pendingAppeals,
        resolved: resolvedAppeals,
        resolutionRate: appealResolutionRate,
      },
      breakdowns: {
        byCategory: categoryBreakdown.map(b => ({ category: b.category, count: b._count.id })),
        byPriority: priorityBreakdown.map(b => ({ priority: b.priority, count: b._count.id })),
        bySource: sourceBreakdown.map(b => ({ source: b.source, count: b._count.id })),
        userStatuses: userStatusBreakdown.map(b => ({ status: b.status, count: b._count.id })),
      },
      dailyTrend,
      period: 'last_30_days',
      generatedAt: now.toISOString(),
    })

  } catch (error) {
    console.error('Moderation stats error:', error)
    return NextResponse.json({ error: 'Failed to fetch stats' }, { status: 500 })
  }
}
