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
exports.FamiliesService = void 0;
const common_1 = require("@nestjs/common");
const prisma_service_1 = require("../../prisma/prisma.service");
const ROLE_HIERARCHY = {
    viewer: 1,
    member: 2,
    editor: 3,
    admin: 4,
};
let FamiliesService = class FamiliesService {
    constructor(prisma) {
        this.prisma = prisma;
    }
    async create(userId, dto) {
        if (!dto.name || typeof dto.name !== 'string' || dto.name.trim().length === 0) {
            throw new common_1.BadRequestException('Family name is required');
        }
        const family = await this.prisma.$transaction(async (tx) => {
            const created = await tx.family.create({
                data: {
                    name: dto.name.trim(),
                    description: dto.description?.trim() || null,
                    primaryLanguage: dto.primaryLanguage || 'en',
                    gotra: dto.gotra?.trim() || null,
                    originVillage: dto.originVillage?.trim() || null,
                    privacyMode: dto.privacyMode || 'private',
                    createdBy: userId,
                    memberCount: 1,
                    lastActivityAt: new Date(),
                },
            });
            await tx.familyMember.create({
                data: {
                    familyId: created.id,
                    userId,
                    role: 'admin',
                },
            });
            return created;
        });
        return this.formatFamily(family);
    }
    async findAll(userId) {
        const memberships = await this.prisma.familyMember.findMany({
            where: { userId },
            include: {
                family: {
                    select: {
                        id: true,
                        name: true,
                        familyCode: true,
                        username: true,
                        description: true,
                        primaryLanguage: true,
                        gotra: true,
                        originVillage: true,
                        privacyMode: true,
                        anchorPersonId: true,
                        memberCount: true,
                        generationCount: true,
                        createdBy: true,
                        avatarUrl: true,
                        region: true,
                        isOnboarded: true,
                        lastActivityAt: true,
                        createdAt: true,
                    },
                },
            },
            orderBy: { joinedAt: 'desc' },
        });
        return memberships.map((m) => this.formatFamily(m.family));
    }
    async findOne(userId, familyId) {
        await this.requireFamilyMember(userId, familyId);
        const family = await this.prisma.family.findUnique({
            where: { id: familyId },
        });
        if (!family) {
            throw new common_1.NotFoundException('Family not found');
        }
        return this.formatFamily(family);
    }
    async update(userId, familyId, dto) {
        await this.requireFamilyRole(userId, familyId, 'editor');
        const existing = await this.prisma.family.findUnique({
            where: { id: familyId },
        });
        if (!existing) {
            throw new common_1.NotFoundException('Family not found');
        }
        const updateData = {};
        if (dto.name !== undefined)
            updateData.name = dto.name.trim();
        if (dto.description !== undefined)
            updateData.description = dto.description?.trim() || null;
        if (dto.primaryLanguage !== undefined)
            updateData.primaryLanguage = dto.primaryLanguage;
        if (dto.gotra !== undefined)
            updateData.gotra = dto.gotra?.trim() || null;
        if (dto.originVillage !== undefined)
            updateData.originVillage = dto.originVillage?.trim() || null;
        if (dto.privacyMode !== undefined)
            updateData.privacyMode = dto.privacyMode;
        if (dto.username !== undefined)
            updateData.username = dto.username?.trim() || null;
        if (dto.avatarUrl !== undefined)
            updateData.avatarUrl = dto.avatarUrl;
        if (dto.region !== undefined)
            updateData.region = dto.region?.trim() || null;
        updateData.lastActivityAt = new Date();
        const updated = await this.prisma.family.update({
            where: { id: familyId },
            data: updateData,
        });
        return this.formatFamily(updated);
    }
    async remove(userId, familyId) {
        await this.requireFamilyRole(userId, familyId, 'admin');
        const family = await this.prisma.family.findUnique({
            where: { id: familyId },
        });
        if (!family) {
            throw new common_1.NotFoundException('Family not found');
        }
        await this.prisma.$transaction(async (tx) => {
            const personIds = await tx.person.findMany({
                where: { familyId },
                select: { id: true },
            });
            const ids = personIds.map((p) => p.id);
            if (ids.length > 0) {
                await tx.relationship.deleteMany({
                    where: {
                        OR: [
                            { fromPersonId: { in: ids } },
                            { toPersonId: { in: ids } },
                        ],
                    },
                });
            }
            await tx.person.deleteMany({ where: { familyId } });
            await tx.familyMember.deleteMany({ where: { familyId } });
            await tx.family.delete({ where: { id: familyId } });
        });
        return { deleted: true, familyId };
    }
    async requireFamilyMember(userId, familyId) {
        const membership = await this.prisma.familyMember.findUnique({
            where: { familyId_userId: { familyId, userId } },
        });
        if (!membership) {
            throw new common_1.ForbiddenException('You are not a member of this family');
        }
        return membership;
    }
    async requireFamilyRole(userId, familyId, minRole) {
        const membership = await this.requireFamilyMember(userId, familyId);
        const userLevel = ROLE_HIERARCHY[membership.role] || 0;
        const requiredLevel = ROLE_HIERARCHY[minRole] || 0;
        if (userLevel < requiredLevel) {
            throw new common_1.ForbiddenException(`Insufficient permissions. Required: ${minRole}, current: ${membership.role}`);
        }
        return membership;
    }
    formatFamily(family) {
        return {
            id: family.id,
            name: family.name,
            familyCode: family.familyCode,
            username: family.username,
            description: family.description,
            primaryLanguage: family.primaryLanguage,
            gotra: family.gotra,
            originVillage: family.originVillage,
            privacyMode: family.privacyMode,
            anchorPersonId: family.anchorPersonId,
            memberCount: family.memberCount,
            generationCount: family.generationCount,
            createdBy: family.createdBy,
            avatarUrl: family.avatarUrl,
            region: family.region,
            isOnboarded: family.isOnboarded,
            lastActivityAt: family.lastActivityAt,
            createdAt: family.createdAt,
        };
    }
};
exports.FamiliesService = FamiliesService;
exports.FamiliesService = FamiliesService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService])
], FamiliesService);
//# sourceMappingURL=families.service.js.map