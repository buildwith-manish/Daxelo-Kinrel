import { NextRequest } from 'next/server';
import { db } from '@/lib/db';
import { success, created, error, collection } from '@/packages/api';

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url);
    const type = searchParams.get('type');
    const q = searchParams.get('q');
    const page = parseInt(searchParams.get('page') ?? '1');
    const limit = Math.min(parseInt(searchParams.get('limit') ?? '20'), 100);

    const where: any = {};
    if (type) where.type = type;
    if (q) where.OR = [{ name: { contains: q } }, { description: { contains: q } }];

    const [communities, total] = await Promise.all([
      db.community.findMany({ where, skip: (page - 1) * limit, take: limit, orderBy: { memberCount: 'desc' }, include: { _count: { select: { members: true } } } }),
      db.community.count({ where }),
    ]);

    return collection(communities, { page, limit, total, hasMore: page * limit < total });
  } catch (err) {
    console.error('[Communities GET] Error:', err);
    return error('INTERNAL_ERROR', 'Failed to fetch communities', 500);
  }
}

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { type, name, description, creatorId, isPrivate } = body;
    if (!type || !name || !creatorId) return error('MISSING_REQUIRED_FIELD', 'type, name, creatorId required', 400);

    const slug = name.toLowerCase().replace(/[^a-z0-9\s-]/g, '').replace(/\s+/g, '-').replace(/-+/g, '-');
    const existing = await db.community.findUnique({ where: { slug } });
    if (existing) return error('CONFLICT', 'Community name already exists', 409);

    const community = await db.community.create({ data: { type, name, slug, description, isPrivate: isPrivate ?? false, memberCount: 1 } });
    await db.communityMember.create({ data: { communityId: community.id, userId: creatorId, role: 'admin', joinedVia: 'creation' } });

    return created({ community });
  } catch (err) {
    console.error('[Communities POST] Error:', err);
    return error('INTERNAL_ERROR', 'Failed to create community', 500);
  }
}
