import { NextRequest } from 'next/server';
import { getServerSession } from 'next-auth';
import { authOptions } from '@/lib/auth';
import { db } from '@/lib/db';
import { success, created, error, collection } from '@/packages/api';

export async function GET() {
  try {
    const session = await getServerSession(authOptions);
    if (!session?.user?.id) return error('AUTH_REQUIRED', 'Unauthorized', 401);

    const memberships = await db.familyMember.findMany({
      where: { userId: session.user.id },
      include: { family: { include: { _count: { select: { members: true, persons: true } } } } },
      orderBy: { joinedAt: 'desc' },
    });

    const families = memberships.map(m => ({
      id: m.family.id,
      name: m.family.name,
      description: m.family.description,
      primaryLanguage: m.family.primaryLanguage,
      gotra: m.family.gotra,
      originVillage: m.family.originVillage,
      role: m.role,
      memberCount: m.family._count.members,
      personCount: m.family._count.persons,
      createdAt: m.family.createdAt,
      updatedAt: m.family.updatedAt,
    }));

    return success(families);
  } catch (err) {
    console.error('[Families GET] Error:', err);
    return error('INTERNAL_ERROR', 'Failed to fetch families', 500);
  }
}

export async function POST(request: NextRequest) {
  try {
    const session = await getServerSession(authOptions);
    if (!session?.user?.id) return error('AUTH_REQUIRED', 'Unauthorized', 401);

    const body = await request.json().catch(() => null);
    if (!body) return error('INVALID_PARAMETER', 'Invalid JSON body', 400);

    const { name, description, primaryLanguage, gotra, originVillage } = body;
    if (!name || typeof name !== 'string' || name.trim().length === 0) {
      return error('MISSING_REQUIRED_FIELD', 'Family name is required', 400);
    }

    const family = await db.family.create({
      data: {
        name: name.trim(),
        description: description?.trim() || null,
        primaryLanguage: primaryLanguage || 'en',
        gotra: gotra?.trim() || null,
        originVillage: originVillage?.trim() || null,
      },
    });

    await db.familyMember.create({ data: { familyId: family.id, userId: session.user.id, role: 'admin' } });
    await db.auditLog.create({ data: { userId: session.user.id, action: 'FAMILY_CREATED', resource: 'Family', resourceId: family.id, details: JSON.stringify({ name: family.name }) } });

    return created({
      family: {
        id: family.id, name: family.name, description: family.description,
        primaryLanguage: family.primaryLanguage, gotra: family.gotra,
        originVillage: family.originVillage, memberCount: 1, personCount: 0, role: 'admin',
        createdAt: family.createdAt, updatedAt: family.updatedAt,
      },
    });
  } catch (err) {
    console.error('[Families POST] Error:', err);
    return error('INTERNAL_ERROR', 'Failed to create family', 500);
  }
}
