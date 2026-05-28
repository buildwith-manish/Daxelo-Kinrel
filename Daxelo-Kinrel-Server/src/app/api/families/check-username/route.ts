// GET /api/families/check-username?username=sharmw
// Check if a family username is available

import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'

export async function GET(request: NextRequest) {
  const username = request.nextUrl.searchParams.get('username')

  if (!username) {
    return NextResponse.json(
      { error: 'Username query parameter is required' },
      { status: 400 }
    )
  }

  // Validate format
  const validPattern = /^[a-z][a-z0-9_]{2,19}$/
  if (!validPattern.test(username)) {
    return NextResponse.json({
      available: false,
      reason: 'Username must be 3-20 chars, start with a letter, and contain only lowercase letters, numbers, and underscores',
    })
  }

  const existing = await db.family.findFirst({
    where: { username },
    select: { id: true },
  })

  if (existing) {
    return NextResponse.json({ available: false, reason: 'Already taken' })
  }

  return NextResponse.json({ available: true })
}
