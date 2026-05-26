// DAXELO KINREL — Pack 09: Community List & Create API
// GET — Search/browse communities  |  POST — Create community

import { NextRequest, NextResponse } from 'next/server';
import { db } from '@/lib/db';

// GET /api/v1/communities — Search/browse communities
export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url);
    const type = searchParams.get('type');
    const query = searchParams.get('q');
    const page = parseInt(searchParams.get('page') ?? '1');
    const limit = Math.min(parseInt(searchParams.get('limit') ?? '20'), 100);
    const skip = (page - 1) * limit;

    const where: Record<string, unknown> = {};

    if (type) {
      where.type = type;
    }

    if (query) {
      where.OR = [
        { name: { contains: query } },
        { description: { contains: query } },
        { gotraName: { contains: query } },
        { villageName: { contains: query } },
        { surname: { contains: query } },
      ];
    }

    const [communities, total] = await Promise.all([
      db.community.findMany({
        where,
        skip,
        take: limit,
        orderBy: { memberCount: 'desc' },
        include: {
          _count: {
            select: { members: true, posts: true, events: true },
          },
        },
      }),
      db.community.count({ where }),
    ]);

    return NextResponse.json({
      communities,
      pagination: {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
      },
    });
  } catch (error) {
    console.error('GET /api/v1/communities error:', error);
    return NextResponse.json(
      { error: 'Failed to fetch communities' },
      { status: 500 }
    );
  }
}

// POST /api/v1/communities — Create a new community
export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const {
      type,
      name,
      description,
      coverImageUrl,
      iconUrl,
      isPrivate,
      gotraName,
      villageName,
      surname,
      region,
      creatorId,
    } = body;

    if (!type || !name || !creatorId) {
      return NextResponse.json(
        { error: 'Missing required fields: type, name, creatorId' },
        { status: 400 }
      );
    }

    // Verify user exists and has moderator+ role
    const user = await db.user.findUnique({ where: { id: creatorId } });
    if (!user) {
      return NextResponse.json({ error: 'User not found' }, { status: 404 });
    }

    if (user.role !== 'admin' && user.role !== 'moderator') {
      return NextResponse.json(
        { error: 'Insufficient permissions. Moderator or admin role required.' },
        { status: 403 }
      );
    }

    // Generate slug from name
    const slug = name
      .toLowerCase()
      .replace(/[^a-z0-9\s-]/g, '')
      .replace(/\s+/g, '-')
      .replace(/-+/g, '-')
      .trim();

    // Check for slug uniqueness
    const existing = await db.community.findUnique({ where: { slug } });
    if (existing) {
      return NextResponse.json(
        { error: 'A community with this name already exists' },
        { status: 409 }
      );
    }

    // Create community
    const community = await db.community.create({
      data: {
        type,
        name,
        slug,
        description,
        coverImageUrl,
        iconUrl,
        isPrivate: isPrivate ?? false,
        gotraName,
        villageName,
        surname,
        region,
        memberCount: 1,
      },
    });

    // Auto-add creator as admin
    await db.communityMember.create({
      data: {
        communityId: community.id,
        userId: creatorId,
        role: 'admin',
        joinedVia: 'creation',
      },
    });

    return NextResponse.json({ community }, { status: 201 });
  } catch (error) {
    console.error('POST /api/v1/communities error:', error);
    return NextResponse.json(
      { error: 'Failed to create community' },
      { status: 500 }
    );
  }
}
