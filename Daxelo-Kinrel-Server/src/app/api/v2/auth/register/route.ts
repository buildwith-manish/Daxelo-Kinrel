import { NextRequest, NextResponse } from 'next/server';
import { z } from 'zod';
import { db } from '@/lib/db';
import CryptoJS from 'crypto-js';
import { success, error, errorFromCode, created } from '@/packages/api';

const registerSchema = z.object({
  name: z.string().min(2).max(100),
  email: z.string().email(),
  password: z.string().min(8).max(100),
});

export async function POST(req: NextRequest) {
  try {
    const body = await req.json().catch(() => null);
    if (!body) return error('INVALID_PARAMETER', 'Invalid JSON body', 400);

    const parsed = registerSchema.safeParse(body);
    if (!parsed.success) {
      const details = parsed.error.issues.map(issue => ({
        path: issue.path.join('.'),
        message: issue.message,
      }));
      return error('VALIDATION_ERROR', 'Request validation failed', 400, details);
    }

    const { name, email, password } = parsed.data;

    const existing = await db.user.findUnique({ where: { email } });
    if (existing) return error('CONFLICT', 'Email already registered', 409);

    const passwordHash = CryptoJS.SHA256(password).toString();
    const user = await db.user.create({
      data: { name, email, passwordHash },
      select: { id: true, email: true, name: true, role: true, preferredLanguage: true, createdAt: true },
    });

    // Auto-create default family
    const family = await db.family.create({ data: { name: `${name}'s Family`, primaryLanguage: 'hi' } });
    await db.familyMember.create({ data: { familyId: family.id, userId: user.id, role: 'admin' } });

    // Audit log
    await db.auditLog.create({
      data: { userId: user.id, action: 'USER_REGISTERED', resource: 'User', resourceId: user.id, details: JSON.stringify({ name, email }) },
    });

    return created({ user, familyId: family.id });
  } catch (err) {
    console.error('[Register] Error:', err);
    return error('INTERNAL_ERROR', 'Failed to register user', 500);
  }
}
