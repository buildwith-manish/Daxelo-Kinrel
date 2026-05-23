// DAXELO KINREL — Pack 09: Personalized Feed API
// GET — Cursor-paginated ranked feed (30 items default)

import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import {
  rankFeedItemAsync,
  deduplicateFeed,
  type FeedItem,
  type FeedItemType,
} from '@/lib/community/feed-ranking';

// GET /api/v1/feed
export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url);
    const userId = searchParams.get('userId');
    const cursor = searchParams.get('cursor');
    const limit = Math.min(parseInt(searchParams.get('limit') ?? '30'), 100);
    const types = searchParams.get('types')?.split(',') as FeedItemType[] | undefined;

    if (!userId) {
      return NextResponse.json({ error: 'userId is required' }, { status: 400 });
    }

    // Get user's family memberships
    const familyMemberships = await db.familyMember.findMany({
      where: { userId },
      select: { familyId: true },
    });
    const familyIds = familyMemberships.map((m) => m.familyId);

    // Get user's community memberships
    const communityMemberships = await db.communityMember.findMany({
      where: { userId },
      select: { communityId: true },
    });
    const communityIds = communityMemberships.map((m) => m.communityId);

    // Build feed items from multiple sources
    const feedItems: Omit<FeedItem, 'score'>[] = [];

    // 1. Birthday items — persons with birthdays in next 30 days
    const upcomingBirthdays = await db.person.findMany({
      where: {
        familyId: { in: familyIds },
        dateOfBirth: { not: null },
        isDeceased: false,
      },
      take: 20,
    });

    for (const person of upcomingBirthdays) {
      if (person.dateOfBirth) {
        feedItems.push({
          id: `birthday-${person.id}`,
          type: 'birthday',
          title: `🎂 ${person.name}'s Birthday`,
          body: `${person.name} has a birthday coming up`,
          authorId: 'system',
          authorName: 'KINREL',
          familyId: person.familyId,
          personId: person.id,
          mediaUrls: [],
          createdAt: person.dateOfBirth,
          reactionCount: 0,
          commentCount: 0,
        });
      }
    }

    // 2. Community posts
    const postsWhere: Record<string, unknown>[] = [];

    if (communityIds.length > 0) {
      postsWhere.push({ communityId: { in: communityIds } });
    }
    if (familyIds.length > 0) {
      postsWhere.push({ familyId: { in: familyIds } });
    }
    postsWhere.push({ visibility: 'public' });

    const posts = await db.communityPost.findMany({
      where: {
        OR: postsWhere,
        isHidden: false,
        ...(cursor ? { createdAt: { lt: new Date(cursor) } } : {}),
      },
      take: limit * 2,
      orderBy: { createdAt: 'desc' },
      include: {
        author: { select: { id: true, name: true } },
        _count: { select: { reactions: true, comments: true } },
      },
    });

    for (const post of posts) {
      feedItems.push({
        id: post.id,
        type: (post.type === 'milestone' ? 'milestone' :
               post.type === 'memorial' ? 'memorial' :
               post.type === 'announcement' ? 'community_post' :
               'community_post') as FeedItemType,
        title: post.title ?? '',
        body: post.body,
        authorId: post.authorId,
        authorName: post.author.name ?? 'Unknown',
        familyId: post.familyId ?? undefined,
        communityId: post.communityId ?? undefined,
        mediaUrls: JSON.parse(post.mediaUrls || '[]'),
        createdAt: post.createdAt,
        reactionCount: post._count.reactions,
        commentCount: post._count.comments,
      });
    }

    // 3. Upcoming events
    const events = await db.communityEvent.findMany({
      where: {
        OR: [
          { familyId: { in: familyIds } },
          { communityId: { in: communityIds } },
          { visibility: 'public' },
        ],
        startDate: { gte: new Date() },
        isCancelled: false,
      },
      take: 10,
      orderBy: { startDate: 'asc' },
      include: {
        _count: { select: { rsvps: true } },
      },
    });

    for (const event of events) {
      feedItems.push({
        id: `event-${event.id}`,
        type: 'event',
        title: event.title,
        body: event.description ?? '',
        authorId: event.creatorId,
        authorName: 'Event',
        familyId: event.familyId ?? undefined,
        communityId: event.communityId ?? undefined,
        eventId: event.id,
        mediaUrls: [],
        createdAt: event.createdAt,
        reactionCount: 0,
        commentCount: event._count.rsvps,
      });
    }

    // 4. New family members
    const newMembers = await db.familyMember.findMany({
      where: {
        familyId: { in: familyIds },
        joinedAt: { gte: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000) },
      },
      take: 10,
      orderBy: { joinedAt: 'desc' },
      include: { user: { select: { id: true, name: true } } },
    });

    for (const member of newMembers) {
      feedItems.push({
        id: `new_member-${member.id}`,
        type: 'new_member',
        title: `👋 ${member.user.name ?? 'New member'} joined the family`,
        body: `${member.user.name ?? 'A new member'} has joined the family tree`,
        authorId: member.userId,
        authorName: member.user.name ?? 'New Member',
        familyId: member.familyId,
        mediaUrls: [],
        createdAt: member.joinedAt,
        reactionCount: 0,
        commentCount: 0,
      });
    }

    // Filter by requested types
    let filtered = types
      ? feedItems.filter((item) => types.includes(item.type))
      : feedItems;

    // Score all items
    const scoredItems: FeedItem[] = await Promise.all(
      filtered.map(async (item) => {
        const score = await rankFeedItemAsync(item, userId);
        return { ...item, score };
      })
    );

    // Deduplicate
    const deduped = deduplicateFeed(scoredItems);

    // Sort by score
    deduped.sort((a, b) => b.score - a.score);

    // Paginate
    const paginated = deduped.slice(0, limit);
    const nextCursor = paginated.length > 0
      ? paginated[paginated.length - 1].createdAt.toISOString()
      : null;

    return NextResponse.json({
      items: paginated,
      pagination: {
        nextCursor,
        hasMore: deduped.length > limit,
        count: paginated.length,
      },
    });
  } catch (error) {
    console.error('GET /api/v1/feed error:', error);
    return NextResponse.json(
      { error: 'Failed to generate feed' },
      { status: 500 }
    );
  }
}
