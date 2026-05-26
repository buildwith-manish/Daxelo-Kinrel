// DAXELO KINREL — Pack 09: Reaction Endpoints
// GET — Aggregated reactions + user's reactions  |  POST — Toggle reaction

import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { getEmojiSet } from '@/lib/community/emoji-set';

interface RouteContext {
  params: Promise<{ postId: string }>;
}

// GET /api/v1/posts/[postId]/reactions
export async function GET(
  request: NextRequest,
  context: RouteContext
) {
  try {
    const { postId } = await context.params;
    const { searchParams } = new URL(request.url);
    const userId = searchParams.get('userId');

    // Get all reactions for this post
    const reactions = await db.reaction.findMany({
      where: { postId },
      include: {
        user: { select: { id: true, name: true } },
      },
    });

    // Aggregate by emoji
    const aggregated: Record<string, { count: number; users: Array<{ id: string; name: string | null }> }> = {};
    for (const reaction of reactions) {
      if (!aggregated[reaction.emoji]) {
        aggregated[reaction.emoji] = { count: 0, users: [] };
      }
      aggregated[reaction.emoji].count++;
      aggregated[reaction.emoji].users.push({
        id: reaction.user.id,
        name: reaction.user.name,
      });
    }

    // Get user's own reactions
    let userReactions: string[] = [];
    if (userId) {
      const myReactions = await db.reaction.findMany({
        where: { postId, userId },
        select: { emoji: true },
      });
      userReactions = myReactions.map((r) => r.emoji);
    }

    // Get appropriate emoji set based on post type
    const post = await db.communityPost.findUnique({
      where: { id: postId },
      select: { type: true },
    });
    const availableEmojis = getEmojiSet(post?.type ?? 'text');

    return NextResponse.json({
      aggregated,
      userReactions,
      availableEmojis,
      totalReactions: reactions.length,
    });
  } catch (error) {
    console.error('GET /api/v1/posts/[postId]/reactions error:', error);
    return NextResponse.json(
      { error: 'Failed to fetch reactions' },
      { status: 500 }
    );
  }
}

// POST /api/v1/posts/[postId]/reactions — Toggle reaction
export async function POST(
  request: NextRequest,
  context: RouteContext
) {
  try {
    const { postId } = await context.params;
    const body = await request.json();
    const { userId, emoji } = body;

    if (!userId || !emoji) {
      return NextResponse.json(
        { error: 'userId and emoji are required' },
        { status: 400 }
      );
    }

    // Verify post exists
    const post = await db.communityPost.findUnique({ where: { id: postId } });
    if (!post) {
      return NextResponse.json({ error: 'Post not found' }, { status: 404 });
    }

    // Validate emoji against context-appropriate set
    const emojiSet = getEmojiSet(post.type);
    const validEmoji = emojiSet.find((e) => e.emoji === emoji);
    if (!validEmoji) {
      // Still allow the reaction but log a warning
      // In production, we might want to be stricter
    }

    // Toggle: if user already reacted with this emoji, remove it
    const existing = await db.reaction.findUnique({
      where: {
        postId_userId_emoji: { postId, userId, emoji },
      },
    });

    if (existing) {
      await db.reaction.delete({
        where: { id: existing.id },
      });

      return NextResponse.json({ action: 'removed', emoji });
    } else {
      await db.reaction.create({
        data: { postId, userId, emoji },
      });

      return NextResponse.json({ action: 'added', emoji }, { status: 201 });
    }
  } catch (error) {
    console.error('POST /api/v1/posts/[postId]/reactions error:', error);
    return NextResponse.json(
      { error: 'Failed to toggle reaction' },
      { status: 500 }
    );
  }
}
