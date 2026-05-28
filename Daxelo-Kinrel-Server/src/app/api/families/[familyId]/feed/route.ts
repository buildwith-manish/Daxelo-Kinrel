// GET /api/families/[familyId]/feed?page=1&limit=10
// Get family feed posts (Instagram-style)
// POST /api/families/[familyId]/feed — Create a new feed post

import { NextRequest, NextResponse } from 'next/server'
import { getServerSession } from 'next-auth'
import { authOptions } from '@/lib/auth'
import { db } from '@/lib/db'

// ── GET — Fetch family feed with pagination ────────────────────────

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ familyId: string }> }
) {
  const { familyId } = await params
  const page = parseInt(request.nextUrl.searchParams.get('page') || '1')
  const limit = parseInt(request.nextUrl.searchParams.get('limit') || '10')
  const skip = (page - 1) * limit

  try {
    const posts = await db.familyPost.findMany({
      where: { familyId },
      include: {
        family: { select: { name: true, username: true } },
        author: { select: { name: true, username: true } },
      },
      orderBy: { createdAt: 'desc' },
      skip,
      take: limit,
    })

    const total = await db.familyPost.count({
      where: { familyId },
    })

    return NextResponse.json({
      posts: posts.map((p) => ({
        id: p.id,
        familyId: p.familyId,
        authorId: p.authorId,
        postType: p.postType,
        content: JSON.parse(p.content),
        reactions: JSON.parse(p.reactions),
        createdAt: p.createdAt,
        familyName: p.family.name,
        familyUsername: p.family.username,
        authorName: p.author.name,
        authorUsername: p.author.username,
      })),
      pagination: {
        page,
        limit,
        total,
        hasMore: skip + posts.length < total,
      },
    })
  } catch (error) {
    console.error('Feed fetch error:', error)
    return NextResponse.json(
      { error: 'Failed to fetch feed' },
      { status: 500 }
    )
  }
}

// ── POST — Create a new feed post ───────────────────────────────────

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ familyId: string }> }
) {
  const session = await getServerSession(authOptions)

  if (!session?.user?.id) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const { familyId } = await params
  const body = await request.json().catch(() => null)
  if (!body) {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 })
  }

  const { postType, content, authorId } = body

  if (!postType || !authorId) {
    return NextResponse.json(
      { error: 'postType and authorId are required' },
      { status: 400 }
    )
  }

  const validTypes = [
    'relationship_discovered',
    'member_joined',
    'milestone',
    'connection_added',
    'invite_shared',
  ]

  if (!validTypes.includes(postType)) {
    return NextResponse.json(
      { error: `Invalid postType. Must be one of: ${validTypes.join(', ')}` },
      { status: 400 }
    )
  }

  try {
    const post = await db.familyPost.create({
      data: {
        familyId,
        authorId,
        postType,
        content: JSON.stringify(content || {}),
        reactions: JSON.stringify({ heart: 0, comment: 0, isHearted: false, isSaved: false }),
      },
      include: {
        family: { select: { name: true, username: true } },
        author: { select: { name: true, username: true } },
      },
    })

    return NextResponse.json(
      {
        post: {
          id: post.id,
          familyId: post.familyId,
          authorId: post.authorId,
          postType: post.postType,
          content: JSON.parse(post.content),
          reactions: JSON.parse(post.reactions),
          createdAt: post.createdAt,
          familyName: post.family.name,
          familyUsername: post.family.username,
          authorName: post.author.name,
          authorUsername: post.author.username,
        },
      },
      { status: 201 }
    )
  } catch (error) {
    console.error('Feed post create error:', error)
    return NextResponse.json(
      { error: 'Failed to create feed post' },
      { status: 500 }
    )
  }
}
