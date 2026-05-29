"use strict";
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.CommunityService = void 0;
const common_1 = require("@nestjs/common");
const prisma_service_1 = require("../../prisma/prisma.service");
let CommunityService = class CommunityService {
    constructor(prisma) {
        this.prisma = prisma;
    }
    async search(params) {
        const { search, type, page = 1, limit = 20 } = params;
        const skip = (page - 1) * limit;
        const where = {};
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
    async create(userId, data) {
        const slug = this.generateSlug(data.name);
        const existing = await this.prisma.community.findUnique({
            where: { slug },
        });
        if (existing) {
            throw new common_1.ConflictException('A community with a similar name already exists');
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
    async findOne(communityId) {
        const community = await this.prisma.community.findUnique({
            where: { id: communityId },
            include: {
                rules: {
                    orderBy: { sortOrder: 'asc' },
                },
            },
        });
        if (!community) {
            throw new common_1.NotFoundException('Community not found');
        }
        return this.formatCommunity(community);
    }
    async join(communityId, userId) {
        const community = await this.prisma.community.findUnique({
            where: { id: communityId },
        });
        if (!community) {
            throw new common_1.NotFoundException('Community not found');
        }
        const existing = await this.prisma.communityMember.findFirst({
            where: { communityId, userId },
        });
        if (existing) {
            throw new common_1.BadRequestException('You are already a member of this community');
        }
        if (community.isPrivate) {
            const member = await this.prisma.communityMember.create({
                data: {
                    communityId,
                    userId,
                    role: 'member',
                },
            });
            await this.prisma.community.update({
                where: { id: communityId },
                data: { memberCount: { increment: 1 } },
            });
            return { joined: true, communityId, role: 'member' };
        }
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
    generateSlug(name) {
        return name
            .toLowerCase()
            .trim()
            .replace(/[^\w\s-]/g, '')
            .replace(/[\s_]+/g, '-')
            .replace(/^-+|-+$/g, '')
            .substring(0, 80);
    }
    formatCommunity(community) {
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
};
exports.CommunityService = CommunityService;
exports.CommunityService = CommunityService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService])
], CommunityService);
//# sourceMappingURL=community.service.js.map