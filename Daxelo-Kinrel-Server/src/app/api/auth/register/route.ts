import { NextRequest, NextResponse } from 'next/server'
import { z } from 'zod'
import { db } from '@/lib/db'
import CryptoJS from 'crypto-js'

const schema = z.object({
  name: z.string().min(2).max(100),
  email: z.string().email(),
  password: z.string().min(8).max(100),
})

export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => null)
  if (!body) return NextResponse.json({ error: 'Invalid JSON' }, { status: 400 })

  const parsed = schema.safeParse(body)
  if (!parsed.success) {
    return NextResponse.json(
      { error: parsed.error.flatten() },
      { status: 400 }
    )
  }

  const { name, email, password } = parsed.data

  const existing = await db.user.findUnique({ where: { email } })
  if (existing) {
    return NextResponse.json({ error: 'Email already registered' }, { status: 409 })
  }

  const passwordHash = CryptoJS.SHA256(password).toString()

  const user = await db.user.create({
    data: { name, email, passwordHash },
    select: { id: true, email: true, name: true },
  })

  // Auto-create a default family for the new user
  const family = await db.family.create({
    data: {
      name: `${name}'s Family`,
      primaryLanguage: 'hi',
    },
  })

  // Add user as admin of their own family
  await db.familyMember.create({
    data: {
      familyId: family.id,
      userId: user.id,
      role: 'admin',
    },
  })

  return NextResponse.json({ user, familyId: family.id }, { status: 201 })
}
