import { NextRequest } from 'next/server';
import { z } from 'zod';
import { db } from '@/lib/db';
import CryptoJS from 'crypto-js';
import { success, error } from '@/packages/api';
import jwt from 'jsonwebtoken';

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
});

export async function POST(req: NextRequest) {
  try {
    const body = await req.json().catch(() => null);
    if (!body) return error('INVALID_PARAMETER', 'Invalid JSON body', 400);

    const parsed = loginSchema.safeParse(body);
    if (!parsed.success) return error('VALIDATION_ERROR', 'Invalid credentials', 400);

    const { email, password } = parsed.data;

    const user = await db.user.findUnique({
      where: { email },
      select: { id: true, email: true, name: true, role: true, passwordHash: true, preferredLanguage: true },
    });

    if (!user || !user.passwordHash) return error('AUTH_REQUIRED', 'Invalid email or password', 401);

    const hash = CryptoJS.SHA256(password).toString();
    if (hash !== user.passwordHash) return error('AUTH_REQUIRED', 'Invalid email or password', 401);

    // Generate JWT tokens
    const secret = process.env.NEXTAUTH_SECRET ?? 'kinrel-dev-secret-change-in-production';
    const accessToken = jwt.sign(
      { id: user.id, email: user.email, role: user.role, preferredLanguage: user.preferredLanguage },
      secret,
      { expiresIn: '15m' },
    );
    const refreshToken = jwt.sign(
      { id: user.id, type: 'refresh' },
      secret,
      { expiresIn: '7d' },
    );

    // Audit log
    await db.auditLog.create({
      data: { userId: user.id, action: 'USER_LOGIN', resource: 'User', resourceId: user.id, details: JSON.stringify({ method: 'credentials' }) },
    });

    return success({
      user: { id: user.id, email: user.email, name: user.name, role: user.role, preferredLanguage: user.preferredLanguage },
      tokens: { accessToken, refreshToken, expiresIn: 900 },
    });
  } catch (err) {
    console.error('[Login] Error:', err);
    return error('INTERNAL_ERROR', 'Login failed', 500);
  }
}
