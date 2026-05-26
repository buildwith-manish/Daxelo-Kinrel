// DAXELO KINREL — Pack 09: Comment Endpoints
// GET — List comments with parentId for threading  |  POST — Create comment

import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';
import { recordContribution } from '@/lib/community/contribution-tracker';

interface RouteContext {
  params: Promise<{ postId: string }>;
}

const MAX_COMMENT_LENGTH = 2000;

// GET /api/v1/posts/[postId]/comments
export async function GET(
  request: NextRequest,
  context: RouteContext
) {
  try {
    const { postId } = await context.params;
    const { searchParams } = new URL(request.url);
    const parentId = searchParams.get('parentId');
    const page = parseInt(searchParams.get('page') ?? '1');
    const limit = Math.min(parseInt(searchParams.get('limit') ?? '50'), 100);
    const skip = (page - 1) * limit;

    const where: Record<string, unknown> = {
      postId,
      isHidden: false,
    };

    // If parentId is provided, get replies to that comment
    // If not provided, get top-level comments (parentId = null)
    if (parentId) {
      where.parentId = parentId;
    } else {
      where.parentId = null;
    }

    const [comments, total] = await Promise.all([
      db.comment.findMany({
        where,
        skip,
        take: limit,
        orderBy: { createdAt: 'asc' },
        include: {
          author: { select: { id: true, name: true } },
        },
      }),
      db.comment.count({ where }),
    ]);

    return NextResponse.json({
      comments,
      pagination: {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
      },
    });
  } catch (error) {
    console.error('GET /api/v1/posts/[postId]/comments error:', error);
    return NextResponse.json(
      { error: 'Failed to fetch comments' },
      { status: 500 }
    );
  }
}

// POST /api/v1/posts/[postId]/comments
export async function POST(
  request: NextRequest,
  context: RouteContext
) {
  try {
    const { postId } = await context.params;
    const body = await request.json();
    const { authorId, parentId, body: commentBody } = body;

    if (!authorId || !commentBody) {
      return NextResponse.json(
        { error: 'authorId and body are required' },
        { status: 400 }
      );
    }

    if (commentBody.length > MAX_COMMENT_LENGTH) {
      return NextResponse.json(
        { error: `Comment exceeds maximum length of ${MAX_COMMENT_LENGTH} characters` },
        { status: 400 }
      );
    }

    if (commentBody.trim().length === 0) {
      return NextResponse.json(
        { error: 'Comment cannot be empty' },
        { status: 400 }
      );
    }

    // Verify post exists
    const post = await db.communityPost.findUnique({ where: { id: postId } });
    if (!post) {
      return NextResponse.json({ error: 'Post not found' }, { status: 404 });
    }

    // Verify post is not locked
    if (post.isLocked) {
      return NextResponse.json(
        { error: 'This post is locked for new comments' },
        { status: 403 }
      );
    }

    // If replying to a parent comment, verify it exists and belongs to same post
    if (parentId) {
      const parentComment = await db.comment.findUnique({
        where: { id: parentId },
      });
      if (!parentComment || parentComment.postId !== postId) {
        return NextResponse.json(
          { error: 'Parent comment not found' },
          { status: 404 }
        );
      }

      // Only allow 1 level of nesting
      if (parentComment.parentId) {
        return NextResponse.json(
          { error: 'Only one level of comment nesting is supported' },
          { status: 400 }
        );
      }
    }

    const comment = await db.comment.create({
      data: {
        postId,
        authorId,
        parentId: parentId ?? null,
        body: commentBody.trim(),
      },
      include: {
        author: { select: { id: true, name: true } },
      },
    });

    // Record contribution
    const authorFamily = await db.familyMember.findFirst({
      where: { userId: authorId },
    });
    if (authorFamily) {
      await recordContribution(authorId, authorFamily.familyId, 'commentWritten');
    }

    return NextResponse.json({ comment }, { status: 201 });
  } catch (error) {
    console.error('POST /api/v1/posts/[postId]/comments error:', error);
    return NextResponse.json(
      { error: 'Failed to create comment' },
      { status: 500 }
    );
  }
}
