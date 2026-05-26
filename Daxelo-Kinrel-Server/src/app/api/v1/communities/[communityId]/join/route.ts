// DAXELO KINREL — Pack 09: Community Join/Leave API
// POST — Join or leave a community

import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { recordContribution } from '@/lib/community/contribution-tracker';

interface RouteContext {
  params: Promise<{ communityId: string }>;
}

// POST /api/v1/communities/[communityId]/join
export async function POST(
  request: NextRequest,
  context: RouteContext
) {
  try {
    const { communityId } = await context.params;
    const body = await request.json();
    const { userId, action } = body; // action: 'join' | 'leave'

    if (!userId) {
      return NextResponse.json({ error: 'userId is required' }, { status: 400 });
    }

    const community = await db.community.findUnique({
      where: { id: communityId },
    });

    if (!community) {
      return NextResponse.json({ error: 'Community not found' }, { status: 404 });
    }

    // Handle LEAVE
    if (action === 'leave') {
      const membership = await db.communityMember.findUnique({
        where: { communityId_userId: { communityId, userId } },
      });

      if (!membership) {
        return NextResponse.json(
          { error: 'Not a member of this community' },
          { status: 400 }
        );
      }

      // Don't allow the last admin to leave
      if (membership.role === 'admin') {
        const adminCount = await db.communityMember.count({
          where: { communityId, role: 'admin' },
        });
        if (adminCount <= 1) {
          return NextResponse.json(
            { error: 'Cannot leave as the last admin. Transfer admin role first.' },
            { status: 400 }
          );
        }
      }

      await db.communityMember.delete({
        where: { communityId_userId: { communityId, userId } },
      });

      // Decrement member count
      await db.community.update({
        where: { id: communityId },
        data: { memberCount: { decrement: 1 } },
      });

      return NextResponse.json({ success: true, action: 'left' });
    }

    // Handle JOIN (default action)
    const existing = await db.communityMember.findUnique({
      where: { communityId_userId: { communityId, userId } },
    });

    if (existing) {
      if (existing.role === 'banned') {
        return NextResponse.json(
          { error: 'You have been banned from this community' },
          { status: 403 }
        );
      }
      return NextResponse.json(
        { error: 'Already a member of this community' },
        { status: 400 }
      );
    }

    // For private communities, check invitation
    let joinVia = 'search';
    if (community.isPrivate) {
      // In production, we'd check for an invite here
      // For now, allow with a flag
      joinVia = 'invitation';
    }

    // Auto-detect join via gotra/village/surname match
    if (community.gotraName || community.villageName || community.surname) {
      const user = await db.user.findUnique({ where: { id: userId } });
      if (user) {
        const userFamilies = await db.familyMember.findMany({
          where: { userId },
          include: { family: true },
        });

        for (const fm of userFamilies) {
          if (community.gotraName && fm.family.gotra === community.gotraName) {
            joinVia = 'auto_gotra';
            break;
          }
          if (community.villageName && fm.family.originVillage === community.villageName) {
            joinVia = 'auto_gotra';
            break;
          }
        }
      }
    }

    await db.communityMember.create({
      data: {
        communityId,
        userId,
        role: 'member',
        joinedVia: joinVia,
      },
    });

    // Increment member count
    await db.community.update({
      where: { id: communityId },
      data: { memberCount: { increment: 1 } },
    });

    // Record contribution if user has a family
    const userFamily = await db.familyMember.findFirst({ where: { userId } });
    if (userFamily) {
      await recordContribution(userId, userFamily.familyId, 'communityJoin');
    }

    return NextResponse.json({ success: true, action: 'joined', joinVia }, { status: 201 });
  } catch (error) {
    console.error('POST /api/v1/communities/[communityId]/join error:', error);
    return NextResponse.json(
      { error: 'Failed to join/leave community' },
      { status: 500 }
    );
  }
}
