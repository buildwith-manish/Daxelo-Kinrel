"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.UsersService = void 0;
const common_1 = require("@nestjs/common");
const prisma_service_1 = require("../../prisma/prisma.service");
const config_1 = require("@nestjs/config");
const bcrypt = __importStar(require("bcryptjs"));
let UsersService = class UsersService {
    constructor(prisma, config) {
        this.prisma = prisma;
        this.config = config;
    }
    async getProfile(userId) {
        const user = await this.prisma.user.findUnique({
            where: { id: userId },
            select: {
                id: true,
                email: true,
                name: true,
                phone: true,
                avatarUrl: true,
                photoThumb: true,
                photoCard: true,
                photoFull: true,
                bio: true,
                dateOfBirth: true,
                gender: true,
                username: true,
                preferredLanguage: true,
                profileVisibility: true,
                invitePermission: true,
                twoFactorEnabled: true,
                authProvider: true,
                createdAt: true,
                updatedAt: true,
            },
        });
        if (!user) {
            throw new common_1.NotFoundException('User not found');
        }
        return { user };
    }
    async getStats(userId) {
        const userFamilies = await this.prisma.familyMember.findMany({
            where: { userId },
            select: { familyId: true },
        });
        const familyIds = userFamilies.map((m) => m.familyId);
        const [familyCount, memberCount, relationCount] = await Promise.all([
            this.prisma.familyMember.count({ where: { userId } }),
            this.prisma.person.count({
                where: {
                    familyId: { in: familyIds },
                    deletedAt: null,
                },
            }),
            this.prisma.relationship.count({
                where: {
                    familyId: { in: familyIds },
                    isActive: true,
                },
            }),
        ]);
        return {
            familyTrees: familyCount,
            membersAdded: memberCount,
            relations: relationCount,
        };
    }
    async updateProfile(userId, data) {
        const updateData = {};
        if (data.name !== undefined)
            updateData.name = data.name.trim();
        if (data.phone !== undefined)
            updateData.phone = data.phone.trim() || null;
        if (data.preferredLanguage !== undefined)
            updateData.preferredLanguage = data.preferredLanguage;
        if (data.username !== undefined)
            updateData.username = data.username.trim() || null;
        if (data.bio !== undefined)
            updateData.bio = data.bio.trim() || null;
        if (data.dateOfBirth !== undefined) {
            updateData.dateOfBirth = data.dateOfBirth
                ? new Date(data.dateOfBirth)
                : null;
        }
        if (data.gender !== undefined)
            updateData.gender = data.gender || null;
        if (data.avatarUrl !== undefined)
            updateData.avatarUrl = data.avatarUrl || null;
        if (data.profileVisibility !== undefined)
            updateData.profileVisibility = data.profileVisibility;
        if (data.invitePermission !== undefined)
            updateData.invitePermission = data.invitePermission;
        const user = await this.prisma.user.update({
            where: { id: userId },
            data: updateData,
            select: {
                id: true,
                email: true,
                name: true,
                phone: true,
                avatarUrl: true,
                photoThumb: true,
                photoCard: true,
                photoFull: true,
                bio: true,
                dateOfBirth: true,
                gender: true,
                username: true,
                preferredLanguage: true,
                profileVisibility: true,
                invitePermission: true,
                twoFactorEnabled: true,
                authProvider: true,
                createdAt: true,
                updatedAt: true,
            },
        });
        return { user };
    }
    async uploadAvatar(userId, file) {
        if (!file) {
            throw new common_1.BadRequestException('No file provided');
        }
        const cloudName = this.config.get('CLOUDINARY_CLOUD_NAME');
        const apiKey = this.config.get('CLOUDINARY_API_KEY');
        const apiSecret = this.config.get('CLOUDINARY_API_SECRET');
        let avatarUrl;
        let photoThumb = null;
        let photoCard = null;
        let photoFull = null;
        if (cloudName && apiKey && apiSecret) {
            const cloudinary = require('cloudinary').v2;
            cloudinary.config({ cloud_name: cloudName, api_key: apiKey, api_secret: apiSecret });
            const uploadResult = await new Promise((resolve, reject) => {
                const uploadStream = cloudinary.uploader.upload_stream({
                    folder: 'kinrel/avatars',
                    public_id: `avatar_${userId}_${Date.now()}`,
                    transformation: [{ width: 512, height: 512, crop: 'fill' }],
                    overwrite: true,
                }, (error, result) => {
                    if (error)
                        reject(error);
                    else
                        resolve(result);
                });
                uploadStream.end(file.buffer);
            });
            const publicId = uploadResult.public_id;
            avatarUrl = uploadResult.secure_url;
            photoThumb = cloudinary.url(publicId, {
                transformation: [{ width: 80, height: 80, crop: 'fill', quality: 'auto', fetch_format: 'auto' }],
            });
            photoCard = cloudinary.url(publicId, {
                transformation: [{ width: 150, height: 150, crop: 'fill', quality: 'auto', fetch_format: 'auto' }],
            });
            photoFull = cloudinary.url(publicId, {
                transformation: [{ width: 400, height: 400, crop: 'fill', quality: 'auto', fetch_format: 'webp' }],
            });
        }
        else {
            const base64 = file.buffer.toString('base64');
            avatarUrl = `data:${file.mimetype};base64,${base64}`;
            photoThumb = avatarUrl;
            photoCard = avatarUrl;
            photoFull = avatarUrl;
        }
        const user = await this.prisma.user.update({
            where: { id: userId },
            data: { avatarUrl, photoThumb, photoCard, photoFull },
            select: {
                id: true,
                email: true,
                name: true,
                phone: true,
                avatarUrl: true,
                photoThumb: true,
                photoCard: true,
                photoFull: true,
                bio: true,
                dateOfBirth: true,
                gender: true,
                username: true,
                preferredLanguage: true,
                profileVisibility: true,
                invitePermission: true,
                twoFactorEnabled: true,
                authProvider: true,
                createdAt: true,
                updatedAt: true,
            },
        });
        return { user };
    }
    async deleteAccount(userId, password) {
        const user = await this.prisma.user.findUnique({
            where: { id: userId },
        });
        if (!user) {
            throw new common_1.NotFoundException('User not found');
        }
        if (password && user.passwordHash) {
            const passwordValid = await bcrypt.compare(password, user.passwordHash);
            if (!passwordValid) {
                throw new common_1.UnauthorizedException('Password is incorrect');
            }
        }
        await this.prisma.$transaction(async (tx) => {
            await tx.refreshToken.deleteMany({ where: { userId } });
            await tx.user.delete({ where: { id: userId } });
        });
        return { success: true, message: 'Account deleted' };
    }
    async checkUsername(username) {
        if (!username || username.trim().length < 3) {
            return { available: false, reason: 'Username must be at least 3 characters' };
        }
        const trimmed = username.trim().toLowerCase();
        const reserved = ['admin', 'root', 'system', 'moderator', 'support', 'help', 'api', 'null', 'undefined'];
        if (reserved.includes(trimmed)) {
            return { available: false, reason: 'This username is reserved' };
        }
        const existingUser = await this.prisma.user.findUnique({
            where: { username: trimmed },
        });
        if (existingUser) {
            return { available: false, reason: 'Username is already taken' };
        }
        const existingPerson = await this.prisma.person.findFirst({
            where: { username: trimmed, deletedAt: null },
        });
        if (existingPerson) {
            return { available: false, reason: 'Username is already taken' };
        }
        return { available: true };
    }
    async updateUsername(userId, username) {
        if (!username || username.trim().length < 3) {
            throw new common_1.BadRequestException('Username must be at least 3 characters');
        }
        const trimmed = username.trim();
        const existingUser = await this.prisma.user.findUnique({
            where: { username: trimmed },
        });
        if (existingUser && existingUser.id !== userId) {
            throw new common_1.ConflictException('Username is already taken');
        }
        const user = await this.prisma.user.update({
            where: { id: userId },
            data: { username: trimmed },
            select: {
                id: true,
                email: true,
                name: true,
                username: true,
                avatarUrl: true,
                photoThumb: true,
            },
        });
        return { user };
    }
    async getFamilies(userId) {
        const memberships = await this.prisma.familyMember.findMany({
            where: { userId },
            include: {
                family: {
                    select: {
                        id: true,
                        name: true,
                        username: true,
                        avatarUrl: true,
                        memberCount: true,
                    },
                },
            },
            orderBy: { joinedAt: 'desc' },
        });
        const families = memberships.map((m) => ({
            id: m.family.id,
            name: m.family.name,
            username: m.family.username,
            role: m.role,
            memberCount: m.family.memberCount,
            avatarUrl: m.family.avatarUrl,
            joinedAt: m.joinedAt,
        }));
        return { families };
    }
    async getInvitations(userId) {
        const user = await this.prisma.user.findUnique({
            where: { id: userId },
            select: { email: true },
        });
        if (!user) {
            throw new common_1.NotFoundException('User not found');
        }
        const invitations = await this.prisma.invitation.findMany({
            where: {
                status: 'pending',
                recipientEmail: user.email,
                expiresAt: { gt: new Date() },
            },
            include: {
                family: {
                    select: {
                        id: true,
                        name: true,
                        avatarUrl: true,
                    },
                },
                inviter: {
                    select: {
                        id: true,
                        name: true,
                        username: true,
                    },
                },
            },
            orderBy: { createdAt: 'desc' },
        });
        const result = invitations.map((inv) => ({
            id: inv.id,
            familyName: inv.family.name,
            familyAvatar: inv.family.avatarUrl,
            inviterName: inv.inviter.name || 'Unknown',
            inviterUsername: inv.inviter.username,
            status: inv.status,
            role: inv.role,
            createdAt: inv.createdAt,
        }));
        return { invitations: result };
    }
    async getBlockedUsers(userId) {
        const user = await this.prisma.user.findUnique({
            where: { id: userId },
            select: { blockedUserIds: true },
        });
        if (!user) {
            throw new common_1.NotFoundException('User not found');
        }
        let blockedIds = [];
        try {
            blockedIds = JSON.parse(user.blockedUserIds || '[]');
        }
        catch {
            blockedIds = [];
        }
        if (blockedIds.length === 0) {
            return { blocked: [] };
        }
        const blockedUsers = await this.prisma.user.findMany({
            where: { id: { in: blockedIds } },
            select: {
                id: true,
                name: true,
                username: true,
                avatarUrl: true,
                photoThumb: true,
            },
        });
        const blocked = blockedUsers.map((u) => ({
            id: u.id,
            name: u.name || 'Unknown',
            username: u.username,
            avatarUrl: u.photoThumb || u.avatarUrl,
            photoThumb: u.photoThumb,
        }));
        return { blocked };
    }
    async unblockUser(userId, blockedUserId) {
        const user = await this.prisma.user.findUnique({
            where: { id: userId },
            select: { blockedUserIds: true },
        });
        if (!user) {
            throw new common_1.NotFoundException('User not found');
        }
        let blockedIds = [];
        try {
            blockedIds = JSON.parse(user.blockedUserIds || '[]');
        }
        catch {
            blockedIds = [];
        }
        if (!blockedIds.includes(blockedUserId)) {
            throw new common_1.NotFoundException('User is not in your blocked list');
        }
        const updatedIds = blockedIds.filter((id) => id !== blockedUserId);
        await this.prisma.user.update({
            where: { id: userId },
            data: { blockedUserIds: JSON.stringify(updatedIds) },
        });
        return { success: true, message: 'User unblocked' };
    }
    async blockUser(userId, targetUserId) {
        if (userId === targetUserId) {
            throw new common_1.BadRequestException('Cannot block yourself');
        }
        const targetUser = await this.prisma.user.findUnique({
            where: { id: targetUserId },
        });
        if (!targetUser) {
            throw new common_1.NotFoundException('Target user not found');
        }
        const user = await this.prisma.user.findUnique({
            where: { id: userId },
            select: { blockedUserIds: true },
        });
        if (!user) {
            throw new common_1.NotFoundException('User not found');
        }
        let blockedIds = [];
        try {
            blockedIds = JSON.parse(user.blockedUserIds || '[]');
        }
        catch {
            blockedIds = [];
        }
        if (blockedIds.includes(targetUserId)) {
            return { success: true, message: 'User already blocked' };
        }
        blockedIds.push(targetUserId);
        await this.prisma.user.update({
            where: { id: userId },
            data: { blockedUserIds: JSON.stringify(blockedIds) },
        });
        return { success: true, message: 'User blocked' };
    }
    async requestDataExport(userId) {
        const user = await this.prisma.user.findUnique({
            where: { id: userId },
            select: {
                id: true,
                email: true,
                name: true,
                phone: true,
                avatarUrl: true,
                photoThumb: true,
                photoCard: true,
                photoFull: true,
                bio: true,
                dateOfBirth: true,
                gender: true,
                username: true,
                preferredLanguage: true,
                profileVisibility: true,
                invitePermission: true,
                twoFactorEnabled: true,
                authProvider: true,
                createdAt: true,
                updatedAt: true,
            },
        });
        if (!user) {
            throw new common_1.NotFoundException('User not found');
        }
        const families = await this.prisma.familyMember.findMany({
            where: { userId },
            include: {
                family: {
                    select: { id: true, name: true, username: true },
                },
            },
        });
        const recentNotifications = await this.prisma.notification.findMany({
            where: { userId },
            orderBy: { createdAt: 'desc' },
            take: 50,
            select: {
                id: true,
                eventType: true,
                title: true,
                body: true,
                read: true,
                createdAt: true,
            },
        });
        const tickets = await this.prisma.supportTicket.findMany({
            where: { userId },
            select: {
                id: true,
                ticketNumber: true,
                subject: true,
                status: true,
                createdAt: true,
            },
        });
        const exportId = `export_${userId}_${Date.now()}`;
        return {
            exportId,
            status: 'completed',
            message: 'Data export completed',
            data: {
                profile: user,
                families: families.map((f) => ({
                    id: f.family.id,
                    name: f.family.name,
                    role: f.role,
                    joinedAt: f.joinedAt,
                })),
                recentNotifications,
                supportTickets: tickets,
            },
            exportedAt: new Date().toISOString(),
        };
    }
    async setQuietHours(userId, data) {
        const existing = await this.prisma.notificationPreference.findUnique({
            where: { userId_eventType: { userId, eventType: 'quiet_hours' } },
        });
        if (existing) {
            const updateData = {};
            if (data.start !== undefined)
                updateData.quietHoursStart = data.start;
            if (data.end !== undefined)
                updateData.quietHoursEnd = data.end;
            if (data.enabled === false) {
                updateData.quietHoursStart = null;
                updateData.quietHoursEnd = null;
            }
            const updated = await this.prisma.notificationPreference.update({
                where: { id: existing.id },
                data: updateData,
            });
            return {
                start: updated.quietHoursStart,
                end: updated.quietHoursEnd,
                enabled: !!(updated.quietHoursStart && updated.quietHoursEnd),
            };
        }
        else {
            const created = await this.prisma.notificationPreference.create({
                data: {
                    userId,
                    eventType: 'quiet_hours',
                    quietHoursStart: data.enabled !== false ? (data.start || null) : null,
                    quietHoursEnd: data.enabled !== false ? (data.end || null) : null,
                },
            });
            return {
                start: created.quietHoursStart,
                end: created.quietHoursEnd,
                enabled: !!(created.quietHoursStart && created.quietHoursEnd),
            };
        }
    }
    async getQuietHours(userId) {
        const pref = await this.prisma.notificationPreference.findUnique({
            where: { userId_eventType: { userId, eventType: 'quiet_hours' } },
        });
        if (!pref) {
            return { start: null, end: null, enabled: false };
        }
        return {
            start: pref.quietHoursStart,
            end: pref.quietHoursEnd,
            enabled: !!(pref.quietHoursStart && pref.quietHoursEnd),
        };
    }
};
exports.UsersService = UsersService;
exports.UsersService = UsersService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        config_1.ConfigService])
], UsersService);
//# sourceMappingURL=users.service.js.map