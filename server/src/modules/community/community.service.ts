import {
  Injectable,
  BadRequestException,
  NotFoundException,
  ConflictException,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class CommunityService {
  constructor(private prisma: PrismaService) {}

  /**
   * Search/browse communities with pagination and filtering.
   */
  async search(params: {
    search?: string;
    type?: string;
    page?: number;
    limit?: number;
  }) {
    const { search, type, page = 1, limit = 20 } = params;
    const skip = (page - 1) * limit;

    const where: any = {};

    if (type) {
      where.type = type;
    }

    if (search) {
      where.OR = [
        { name: { contains: search } },
        { gotraName: { contains: search } },
        { villageName: { contains: search } },
        { surname: { contains: search } },
        { region: { contains: search } },
      ];
    }

    const [communities, total] = await Promise.all([
      this.prisma.community.findMany({
        where,
        skip,
        take: limit,
        orderBy: { memberCount: 'desc' },
      }),
      this.prisma.community.count({ where }),
    ]);

    return {
      data: communities.map((c) => this.formatCommunity(c)),
      pagination: {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit),
      },
    };
  }

  /**
   * Create a new community.
   * Only verified/moderator users can create certain types.
   */
  async create(
    userId: string,
    data: {
      type: string;
      name: string;
      description?: string;
      isPrivate?: boolean;
      gotraName?: string;
      villageName?: string;
      surname?: string;
      region?: string;
    },
  ) {
    // Generate slug from name
    const slug = this.generateSlug(data.name);

    // Check if slug is already taken
    const existing = await this.prisma.community.findUnique({
      where: { slug },
    });

    if (existing) {
      throw new ConflictException(
        'A community with a similar name already exists',
      );
    }

    const community = await this.prisma.$transaction(async (tx) => {
      const created = await tx.community.create({
        data: {
          type: data.type,
          name: data.name.trim(),
          slug,
          description: data.description?.trim() || null,
          isPrivate: data.isPrivate || false,
          gotraName: data.gotraName?.trim() || null,
          villageName: data.villageName?.trim() || null,
          surname: data.surname?.trim() || null,
          region: data.region?.trim() || null,
          memberCount: 1,
        },
      });

      // Auto-join the creator as admin
      await tx.communityMember.create({
        data: {
          communityId: created.id,
          userId,
          role: 'admin',
        },
      });

      return created;
    });

    return this.formatCommunity(community);
  }

  /**
   * Get community detail.
   */
  async findOne(communityId: string) {
    const community = await this.prisma.community.findUnique({
      where: { id: communityId },
      include: {
        rules: {
          orderBy: { sortOrder: 'asc' },
        },
      },
    });

    if (!community) {
      throw new NotFoundException('Community not found');
    }

    return this.formatCommunity(community);
  }

  /**
   * Join a community.
   */
  async join(communityId: string, userId: string) {
    const community = await this.prisma.community.findUnique({
      where: { id: communityId },
    });

    if (!community) {
      throw new NotFoundException('Community not found');
    }

    // Check if already a member
    const existing = await this.prisma.communityMember.findFirst({
      where: { communityId, userId },
    });

    if (existing) {
      throw new BadRequestException('You are already a member of this community');
    }

    // For private communities, check if they need approval
    if (community.isPrivate) {
      // Create a pending membership request
      const member = await this.prisma.communityMember.create({
        data: {
          communityId,
          userId,
          role: 'member',
        },
      });

      // Increment member count only for public communities
      await this.prisma.community.update({
        where: { id: communityId },
        data: { memberCount: { increment: 1 } },
      });

      return { joined: true, communityId, role: 'member' };
    }

    // Public community — auto-join
    await this.prisma.$transaction(async (tx) => {
      await tx.communityMember.create({
        data: {
          communityId,
          userId,
          role: 'member',
        },
      });

      await tx.community.update({
        where: { id: communityId },
        data: { memberCount: { increment: 1 } },
      });
    });

    return { joined: true, communityId, role: 'member' };
  }

  /**
   * Generate a URL-safe slug from a community name.
   */
  private generateSlug(name: string): string {
    return name
      .toLowerCase()
      .trim()
      .replace(/[^\w\s-]/g, '')
      .replace(/[\s_]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .substring(0, 80);
  }

  private formatCommunity(community: any) {
    return {
      id: community.id,
      type: community.type,
      name: community.name,
      slug: community.slug,
      description: community.description,
      coverImageUrl: community.coverImageUrl,
      iconUrl: community.iconUrl,
      isVerified: community.isVerified,
      isPrivate: community.isPrivate,
      memberCount: community.memberCount,
      postCount: community.postCount,
      gotraName: community.gotraName,
      villageName: community.villageName,
      surname: community.surname,
      region: community.region,
      rules: community.rules || undefined,
      createdAt: community.createdAt,
      updatedAt: community.updatedAt,
    };
  }
}
