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
exports.UsersService = void 0;
const common_1 = require("@nestjs/common");
const prisma_service_1 = require("../prisma/prisma.service");
let UsersService = class UsersService {
    constructor(prisma) {
        this.prisma = prisma;
    }
    async getOrCreateUser(id, email) {
        let user = await this.prisma.user.findUnique({ where: { id } });
        if (!user) {
            user = await this.prisma.user.create({
                data: {
                    id,
                    email,
                    name: email.split('@')[0],
                },
            });
        }
        return user;
    }
    async getProfile(id) {
        const user = await this.prisma.user.findUnique({ where: { id } });
        if (!user)
            return null;
        const { twoFactorSecret, ...safeUser } = user;
        return safeUser;
    }
    async updateProfile(id, data) {
        const allowedFields = [
            'name', 'phone', 'avatarUrl', 'bio', 'dateOfBirth',
            'gender', 'preferredLanguage', 'profileVisibility', 'invitePermission',
        ];
        const updateData = {};
        for (const field of allowedFields) {
            if (data[field] !== undefined) {
                updateData[field] = data[field];
            }
        }
        return this.prisma.user.update({
            where: { id },
            data: updateData,
        });
    }
    async updateAvatar(id, avatarUrl) {
        return this.prisma.user.update({
            where: { id },
            data: { avatarUrl },
        });
    }
    async getStats(id) {
        const familyTrees = await this.prisma.familyMember.count({
            where: { userId: id },
        });
        const familyIds = await this.prisma.familyMember.findMany({
            where: { userId: id },
            select: { familyId: true },
        });
        const familyIdList = familyIds.map((f) => f.familyId);
        const membersAdded = await this.prisma.person.count({
            where: { familyId: { in: familyIdList } },
        });
        const relations = await this.prisma.relationship.count({
            where: { familyId: { in: familyIdList } },
        });
        return {
            familyTrees,
            membersAdded,
            relations,
        };
    }
    async checkUsername(username) {
        const existing = await this.prisma.user.findUnique({
            where: { username },
        });
        return { available: !existing };
    }
    async setUsername(id, username) {
        const existing = await this.prisma.user.findUnique({
            where: { username },
        });
        if (existing && existing.id !== id) {
            return { error: 'Username already taken' };
        }
        return this.prisma.user.update({
            where: { id },
            data: { username },
        });
    }
    async getFamilies(id) {
        const memberships = await this.prisma.familyMember.findMany({
            where: { userId: id },
            include: { family: true },
        });
        return memberships.map((m) => ({
            ...m.family,
            role: m.role,
            joinedAt: m.joinedAt,
        }));
    }
    async getInvitations(id) {
        return this.prisma.invitation.findMany({
            where: { inviterId: id, status: 'pending' },
        });
    }
    async getBlocked(id) {
        return { blocked: [] };
    }
    async unblockUser(id, blockedUserId) {
        return { message: 'User unblocked' };
    }
    async requestDataExport(id) {
        return { message: 'Data export requested', exportId: id + '-export-' + Date.now() };
    }
    async deleteAccount(id) {
        await this.prisma.refreshToken.deleteMany({ where: { userId: id } });
        await this.prisma.familyMember.deleteMany({ where: { userId: id } });
        await this.prisma.invitation.deleteMany({ where: { inviterId: id } });
        await this.prisma.supportTicket.deleteMany({ where: { userId: id } });
        await this.prisma.user.delete({ where: { id } });
        return { message: 'Account deleted successfully' };
    }
    async updateQuietHours(id, data) {
        return { message: 'Quiet hours updated', quietHours: data };
    }
};
exports.UsersService = UsersService;
exports.UsersService = UsersService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService])
], UsersService);
//# sourceMappingURL=users.service.js.map