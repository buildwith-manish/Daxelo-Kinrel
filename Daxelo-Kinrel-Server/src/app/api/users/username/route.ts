// POST /api/users/username
// Set username for the current user

import { NextRequest, NextResponse } from 'next/server'
import { getServerSession } from 'next-auth'
import { authOptions } from '@/lib/auth'
import { db } from '@/lib/db'

export async function POST(request: NextRequest) {
  const session = await getServerSession(authOptions)

  if (!session?.user?.id) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  }

  const body = await request.json().catch(() => null)
  if (!body) {
    return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 })
  }

  const { username } = body

  if (!username || typeof username !== 'string') {
    return NextResponse.json(
      { error: 'Username is required' },
      { status: 400 }
    )
  }

  // Validate format
  const validPattern = /^[a-z][a-z0-9_]{2,19}$/
  if (!validPattern.test(username)) {
    return NextResponse.json(
      { error: 'Username must be 3-20 chars, start with a letter, and contain only lowercase letters, numbers, and underscores' },
      { status: 400 }
    )
  }

  // Check availability
  const existingUser = await db.user.findFirst({
    where: { username },
    select: { id: true },
  })

  if (existingUser) {
    return NextResponse.json(
      { error: 'Username is already taken' },
      { status: 409 }
    )
  }

  // Update user
  const updatedUser = await db.user.update({
    where: { id: session.user.id },
    data: { username },
    select: { id: true, username: true },
  })

  return NextResponse.json({
    user: updatedUser,
    message: 'Username set successfully',
  })
}
