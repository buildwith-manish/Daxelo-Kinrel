// GET /api/users/check-username?username=manish
// Check if a person username is available

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

  // Validate format: 3-20 chars, lowercase letters, numbers, underscores, starts with letter
  const validPattern = /^[a-z][a-z0-9_]{2,19}$/
  if (!validPattern.test(username)) {
    return NextResponse.json({
      available: false,
      reason: 'Username must be 3-20 chars, start with a letter, and contain only lowercase letters, numbers, and underscores',
    })
  }

  // Check User table
  const existingUser = await db.user.findFirst({
    where: { username },
    select: { id: true },
  })

  if (existingUser) {
    return NextResponse.json({ available: false, reason: 'Already taken' })
  }

  // Check Person table too
  const existingPerson = await db.person.findFirst({
    where: { username },
    select: { id: true },
  })

  if (existingPerson) {
    return NextResponse.json({ available: false, reason: 'Already taken' })
  }

  return NextResponse.json({ available: true })
}
