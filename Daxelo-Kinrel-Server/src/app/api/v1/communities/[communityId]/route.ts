// DAXELO KINREL — Pack 09: Community Detail API
// GET — Community detail + stats  |  PATCH — Update  |  DELETE — Delete

import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';

interface RouteContext {
  params: Promise<{ communityId: string }>;
}

// GET /api/v1/communities/[communityId]
export async function GET(
  _request: NextRequest,
  context: RouteContext
) {
  try {
    const { communityId } = await context.params;

    const community = await db.community.findUnique({
      where: { id: communityId },
      include: {
        members: {
          take: 10,
          orderBy: { joinedAt: 'desc' },
          include: {
            user: { select: { id: true, name: true, email: true } },
          },
        },
        rules: { orderBy: { sortOrder: 'asc' } },
        _count: {
          select: { members: true, posts: true, events: true },
        },
      },
    });

    if (!community) {
      return NextResponse.json(
        { error: 'Community not found' },
        { status: 404 }
      );
    }

    // Stats
    const recentPosts = await db.communityPost.count({
      where: {
        communityId,
        createdAt: { gte: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000) },
      },
    });

    return NextResponse.json({
      community,
      stats: {
        totalMembers: community._count.members,
        totalPosts: community._count.posts,
        totalEvents: community._count.events,
        recentPostsThisWeek: recentPosts,
      },
    });
  } catch (error) {
    console.error('GET /api/v1/communities/[communityId] error:', error);
    return NextResponse.json(
      { error: 'Failed to fetch community' },
      { status: 500 }
    );
  }
}

// PATCH /api/v1/communities/[communityId]
export async function PATCH(
  request: NextRequest,
  context: RouteContext
) {
  try {
    const { communityId } = await context.params;
    const body = await request.json();
    const { userId, name, description, coverImageUrl, iconUrl, isPrivate, isVerified, region } = body;

    if (!userId) {
      return NextResponse.json({ error: 'userId is required' }, { status: 400 });
    }

    // Check admin membership
    const membership = await db.communityMember.findFirst({
      where: { communityId, userId, role: 'admin' },
    });

    if (!membership) {
      return NextResponse.json(
        { error: 'Only community admins can update the community' },
        { status: 403 }
      );
    }

    const updateData: Record<string, unknown> = {};
    if (name !== undefined) updateData.name = name;
    if (description !== undefined) updateData.description = description;
    if (coverImageUrl !== undefined) updateData.coverImageUrl = coverImageUrl;
    if (iconUrl !== undefined) updateData.iconUrl = iconUrl;
    if (isPrivate !== undefined) updateData.isPrivate = isPrivate;
    if (region !== undefined) updateData.region = region;

    // Only system admins can verify
    if (isVerified !== undefined) {
      const user = await db.user.findUnique({ where: { id: userId } });
      if (user?.role === 'admin') {
        updateData.isVerified = isVerified;
      }
    }

    const community = await db.community.update({
      where: { id: communityId },
      data: updateData,
    });

    return NextResponse.json({ community });
  } catch (error) {
    console.error('PATCH /api/v1/communities/[communityId] error:', error);
    return NextResponse.json(
      { error: 'Failed to update community' },
      { status: 500 }
    );
  }
}

// DELETE /api/v1/communities/[communityId]
export async function DELETE(
  request: NextRequest,
  context: RouteContext
) {
  try {
    const { communityId } = await context.params;
    const { searchParams } = new URL(request.url);
    const userId = searchParams.get('userId');

    if (!userId) {
      return NextResponse.json({ error: 'userId is required' }, { status: 400 });
    }

    // Check admin membership
    const membership = await db.communityMember.findFirst({
      where: { communityId, userId, role: 'admin' },
    });

    if (!membership) {
      return NextResponse.json(
        { error: 'Only community admins can delete the community' },
        { status: 403 }
      );
    }

    await db.community.delete({ where: { id: communityId } });

    return NextResponse.json({ success: true });
  } catch (error) {
    console.error('DELETE /api/v1/communities/[communityId] error:', error);
    return NextResponse.json(
      { error: 'Failed to delete community' },
      { status: 500 }
    );
  }
}
