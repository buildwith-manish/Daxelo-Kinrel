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
const prisma_service_1 = require("../prisma/prisma.service");
let FamiliesService = class FamiliesService {
    constructor(prisma) {
        this.prisma = prisma;
    }
    async listFamilies(userId) {
        const memberships = await this.prisma.familyMember.findMany({
            where: { userId },
            include: { family: { include: { persons: true } } },
        });
        return memberships.map((m) => ({
            ...m.family,
            role: m.role,
            joinedAt: m.joinedAt,
        }));
    }
    async createFamily(userId, data) {
        const familyCode = Math.random().toString(36).substring(2, 8).toUpperCase();
        const family = await this.prisma.family.create({
            data: {
                name: data.name,
                username: data.username || null,
                familyCode,
                avatarUrl: data.avatarUrl || null,
                region: data.region || null,
                privacyMode: data.privacyMode || 'public',
                isOnboarded: false,
                createdBy: userId,
                description: data.description || null,
                primaryLanguage: data.primaryLanguage || 'en',
                gotra: data.gotra || null,
                originVillage: data.originVillage || null,
                memberCount: 1,
                generationCount: 1,
            },
        });
        await this.prisma.familyMember.create({
            data: {
                familyId: family.id,
                userId,
                role: 'admin',
            },
        });
        return family;
    }
    async getFamily(userId, familyId) {
        const membership = await this.prisma.familyMember.findUnique({
            where: { familyId_userId: { familyId, userId } },
        });
        if (!membership) {
            throw new common_1.ForbiddenException('Not a member of this family');
        }
        const family = await this.prisma.family.findUnique({
            where: { id: familyId },
            include: {
                persons: { where: { deletedAt: null } },
                members: true,
            },
        });
        if (!family) {
            throw new common_1.NotFoundException('Family not found');
        }
        return {
            ...family,
            role: membership.role,
        };
    }
    async updateFamily(userId, familyId, data) {
        const membership = await this.prisma.familyMember.findUnique({
            where: { familyId_userId: { familyId, userId } },
        });
        if (!membership || membership.role !== 'admin') {
            throw new common_1.ForbiddenException('Only admins can update family');
        }
        const allowedFields = [
            'name', 'username', 'avatarUrl', 'region', 'privacyMode',
            'isOnboarded', 'anchorPersonId', 'memberCount', 'generationCount',
            'description', 'primaryLanguage', 'gotra', 'originVillage',
        ];
        const updateData = {};
        for (const field of allowedFields) {
            if (data[field] !== undefined) {
                updateData[field] = data[field];
            }
        }
        return this.prisma.family.update({
            where: { id: familyId },
            data: updateData,
        });
    }
    async deleteFamily(userId, familyId) {
        const membership = await this.prisma.familyMember.findUnique({
            where: { familyId_userId: { familyId, userId } },
        });
        if (!membership || membership.role !== 'admin') {
            throw new common_1.ForbiddenException('Only admins can delete family');
        }
        await this.prisma.relationship.deleteMany({ where: { familyId } });
        await this.prisma.person.deleteMany({ where: { familyId } });
        await this.prisma.familyMember.deleteMany({ where: { familyId } });
        await this.prisma.family.delete({ where: { id: familyId } });
        return { message: 'Family deleted successfully' };
    }
    async exportFamily(userId, familyId) {
        const membership = await this.prisma.familyMember.findUnique({
            where: { familyId_userId: { familyId, userId } },
        });
        if (!membership) {
            throw new common_1.ForbiddenException('Not a member of this family');
        }
        const family = await this.prisma.family.findUnique({
            where: { id: familyId },
            include: {
                persons: { where: { deletedAt: null } },
            },
        });
        return {
            export: family,
            exportedAt: new Date().toISOString(),
            format: 'json',
        };
    }
};
exports.FamiliesService = FamiliesService;
exports.FamiliesService = FamiliesService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService])
], FamiliesService);
//# sourceMappingURL=families.service.js.map