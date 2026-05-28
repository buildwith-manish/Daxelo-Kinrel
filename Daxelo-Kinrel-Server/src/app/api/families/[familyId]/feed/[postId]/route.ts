// POST /api/families/[familyId]/feed/[postId]/react
// React to a feed post (heart, etc.)

import { NextRequest, NextResponse } from 'next/server'
import { getServerSession } from 'next-auth'
import { authOptions } from '@/lib/auth'
import { db } from '@/lib/db'

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ familyId: string; postId: string }> }
) {
  const session = await getServerSession(authOptions)

  if (!session?.user?.id) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const { postId } = await params
  const body = await request.json().catch(() => null)
  if (!body) {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 })
  }

  const { type, value } = body // type: "heart" | "save", value: true | false

  try {
    const post = await db.familyPost.findUnique({
      where: { id: postId },
      select: { reactions: true },
    })

    if (!post) {
      return NextResponse.json({ error: 'Post not found' }, { status: 404 })
    }

    const reactions = JSON.parse(post.reactions || '{}')

    if (type === 'heart') {
      const currentCount = reactions.heart || 0
      reactions.heart = value ? currentCount + 1 : Math.max(0, currentCount - 1)
      reactions.isHearted = value
    } else if (type === 'save') {
      reactions.isSaved = value
    }

    const updated = await db.familyPost.update({
      where: { id: postId },
      data: { reactions: JSON.stringify(reactions) },
    })

    return NextResponse.json({
      reactions: JSON.parse(updated.reactions),
    })
  } catch (error) {
    console.error('React error:', error)
    return NextResponse.json(
      { error: 'Failed to react to post' },
      { status: 500 }
    )
  }
}
