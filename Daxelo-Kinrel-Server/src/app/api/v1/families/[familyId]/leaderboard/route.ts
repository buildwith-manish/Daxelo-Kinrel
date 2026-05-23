// DAXELO KINREL — Pack 09: Family Leaderboard API
// GET — Family leaderboard with contribution stats

import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { getLevel } from '@/lib/community/contribution-tracker';

interface RouteContext {
  params: Promise<{ familyId: string }>;
}

// GET /api/v1/families/[familyId]/leaderboard
export async function GET(
  request: NextRequest,
  context: RouteContext
) {
  try {
    const { familyId } = await context.params;
    const { searchParams } = new URL(request.url);
    const period = searchParams.get('period') ?? 'all'; // all, monthly, weekly
    const page = parseInt(searchParams.get('page') ?? '1');
    const limit = Math.min(parseInt(searchParams.get('limit') ?? '25'), 100);
    const skip = (page - 1) * limit;

    // Verify family exists
    const family = await db.family.findUnique({ where: { id: familyId } });
    if (!family) {
      return NextResponse.json({ error: 'Family not found' }, { status: 404 });
    }

    // Get contributions ordered by total points
    const where: Record<string, unknown> = { familyId };

    // For time-based periods, we'd need to filter by date
    // Since contributions are cumulative, we'll show all-time for now
    // and note the period parameter for future implementation

    const [contributions, total] = await Promise.all([
      db.userContribution.findMany({
        where,
        skip,
        take: limit,
        orderBy: { totalPoints: 'desc' },
        include: {
          user: { select: { id: true, name: true, email: true } },
        },
      }),
      db.userContribution.count({ where }),
    ]);

    // Enrich with level info and badges
    const leaderboard = contributions.map((c, index) => {
      const levelInfo = getLevel(c.totalPoints);
      const rank = skip + index + 1;

      return {
        rank,
        userId: c.userId,
        userName: c.user.name ?? c.user.email,
        totalPoints: c.totalPoints,
        level: levelInfo,
        stats: {
          personsAdded: c.personsAdded,
          relationshipsAdded: c.relationshipsAdded,
          photosAdded: c.photosAdded,
          eventsCreated: c.eventsCreated,
          storiesShared: c.storiesShared,
          commentsWritten: c.commentsWritten,
          invitationsSent: c.invitationsSent,
          personsEdited: c.personsEdited,
        },
      };
    });

    // Get family badge summary
    const familyBadges = await db.userBadge.findMany({
      where: { familyId },
      include: {
        badge: true,
        user: { select: { id: true, name: true } },
      },
      orderBy: { earnedAt: 'desc' },
      take: 10,
    });

    // Get family milestones
    const milestones = await db.familyMilestone.findMany({
      where: { familyId },
      orderBy: { reachedAt: 'desc' },
    });

    // Aggregate family totals
    const familyTotals = await db.userContribution.aggregate({
      where: { familyId },
      _sum: {
        totalPoints: true,
        personsAdded: true,
        relationshipsAdded: true,
        photosAdded: true,
      },
    });

    return NextResponse.json({
      family: {
        id: family.id,
        name: family.name,
      },
      leaderboard,
      badges: familyBadges.map((ub) => ({
        badge: {
          id: ub.badge.id,
          slug: ub.badge.slug,
          name: ub.badge.name,
          nameHi: ub.badge.nameHi,
          icon: ub.badge.icon,
          tier: ub.badge.tier,
        },
        earnedBy: ub.user.name,
        earnedAt: ub.earnedAt,
      })),
      milestones,
      totals: {
        totalPoints: familyTotals._sum.totalPoints ?? 0,
        personsAdded: familyTotals._sum.personsAdded ?? 0,
        relationshipsAdded: familyTotals._sum.relationshipsAdded ?? 0,
        photosAdded: familyTotals._sum.photosAdded ?? 0,
      },
      pagination: {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
      },
    });
  } catch (error) {
    console.error('GET /api/v1/families/[familyId]/leaderboard error:', error);
    return NextResponse.json(
      { error: 'Failed to fetch leaderboard' },
      { status: 500 }
    );
  }
}
