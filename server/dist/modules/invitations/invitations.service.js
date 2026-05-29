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
exports.InvitationsService = void 0;
const common_1 = require("@nestjs/common");
const prisma_service_1 = require("../../prisma/prisma.service");
const crypto_1 = require("crypto");
let InvitationsService = class InvitationsService {
    constructor(prisma) {
        this.prisma = prisma;
    }
    async create(userId, data) {
        const membership = await this.prisma.familyMember.findUnique({
            where: {
                familyId_userId: { familyId: data.familyId, userId },
            },
        });
        if (!membership) {
            throw new common_1.ForbiddenException('You are not a member of this family');
        }
        if (membership.role !== 'admin' && membership.role !== 'editor') {
            throw new common_1.ForbiddenException('Only admins and editors can send invitations');
        }
        const family = await this.prisma.family.findUnique({
            where: { id: data.familyId },
        });
        if (!family) {
            throw new common_1.NotFoundException('Family not found');
        }
        const token = (0, crypto_1.randomBytes)(24).toString('hex');
        const expiresAt = new Date();
        expiresAt.setDate(expiresAt.getDate() + 7);
        const invitation = await this.prisma.invitation.create({
            data: {
                token,
                familyId: data.familyId,
                inviterId: userId,
                recipientEmail: data.recipientEmail || null,
                recipientPhone: data.recipientPhone || null,
                recipientName: data.recipientName || null,
                role: data.role || 'member',
                channel: data.channel || (data.recipientPhone ? 'whatsapp' : 'email'),
                expiresAt,
            },
            include: {
                family: { select: { id: true, name: true, familyCode: true } },
                inviter: { select: { id: true, name: true, email: true } },
            },
        });
        return this.formatInvitation(invitation);
    }
    async findByFamily(familyId, userId) {
        const membership = await this.prisma.familyMember.findUnique({
            where: {
                familyId_userId: { familyId, userId },
            },
        });
        if (!membership) {
            throw new common_1.ForbiddenException('You are not a member of this family');
        }
        const invitations = await this.prisma.invitation.findMany({
            where: { familyId, status: { in: ['pending', 'accepted'] } },
            include: {
                inviter: { select: { id: true, name: true, email: true } },
            },
            orderBy: { createdAt: 'desc' },
        });
        return invitations.map((inv) => this.formatInvitation(inv));
    }
    async acceptById(invitationId, userId) {
        const invitation = await this.prisma.invitation.findUnique({
            where: { id: invitationId },
        });
        if (!invitation) {
            throw new common_1.NotFoundException('Invitation not found');
        }
        if (invitation.status !== 'pending') {
            throw new common_1.BadRequestException(`Invitation is already ${invitation.status}`);
        }
        if (invitation.expiresAt && invitation.expiresAt < new Date()) {
            await this.prisma.invitation.update({
                where: { id: invitationId },
                data: { status: 'expired' },
            });
            throw new common_1.BadRequestException('Invitation has expired');
        }
        return this.acceptInvitation(invitation, userId);
    }
    async declineById(invitationId, userId) {
        const invitation = await this.prisma.invitation.findUnique({
            where: { id: invitationId },
        });
        if (!invitation) {
            throw new common_1.NotFoundException('Invitation not found');
        }
        if (invitation.status !== 'pending') {
            throw new common_1.BadRequestException(`Invitation is already ${invitation.status}`);
        }
        const updated = await this.prisma.invitation.update({
            where: { id: invitationId },
            data: { status: 'cancelled' },
        });
        return { accepted: false, invitationId: updated.id, status: updated.status };
    }
    async acceptByToken(token, userId) {
        const invitation = await this.prisma.invitation.findUnique({
            where: { token },
        });
        if (!invitation) {
            throw new common_1.NotFoundException('Invitation not found');
        }
        if (invitation.status !== 'pending') {
            throw new common_1.BadRequestException(`Invitation is already ${invitation.status}`);
        }
        if (invitation.expiresAt && invitation.expiresAt < new Date()) {
            await this.prisma.invitation.update({
                where: { token },
                data: { status: 'expired' },
            });
            throw new common_1.BadRequestException('Invitation has expired');
        }
        return this.acceptInvitation(invitation, userId);
    }
    async cancel(invitationId, userId) {
        const invitation = await this.prisma.invitation.findUnique({
            where: { id: invitationId },
        });
        if (!invitation) {
            throw new common_1.NotFoundException('Invitation not found');
        }
        if (invitation.inviterId !== userId) {
            const membership = await this.prisma.familyMember.findUnique({
                where: {
                    familyId_userId: { familyId: invitation.familyId, userId },
                },
            });
            if (!membership || membership.role !== 'admin') {
                throw new common_1.ForbiddenException('Only the inviter or a family admin can cancel this invitation');
            }
        }
        if (invitation.status !== 'pending') {
            throw new common_1.BadRequestException(`Cannot cancel an invitation that is ${invitation.status}`);
        }
        const updated = await this.prisma.invitation.update({
            where: { id: invitationId },
            data: { status: 'cancelled' },
        });
        return { cancelled: true, invitationId: updated.id };
    }
    async acceptInvitation(invitation, userId) {
        const existing = await this.prisma.familyMember.findUnique({
            where: {
                familyId_userId: { familyId: invitation.familyId, userId },
            },
        });
        if (existing) {
            throw new common_1.BadRequestException('You are already a member of this family');
        }
        const result = await this.prisma.$transaction(async (tx) => {
            await tx.familyMember.create({
                data: {
                    familyId: invitation.familyId,
                    userId,
                    role: invitation.role,
                },
            });
            await tx.family.update({
                where: { id: invitation.familyId },
                data: {
                    memberCount: { increment: 1 },
                    lastActivityAt: new Date(),
                },
            });
            const updated = await tx.invitation.update({
                where: { id: invitation.id },
                data: {
                    status: 'accepted',
                    acceptedAt: new Date(),
                },
            });
            return updated;
        });
        return {
            accepted: true,
            invitationId: result.id,
            familyId: invitation.familyId,
            role: invitation.role,
        };
    }
    formatInvitation(inv) {
        return {
            id: inv.id,
            token: inv.token,
            familyId: inv.familyId,
            inviterId: inv.inviterId,
            family: inv.family || undefined,
            inviter: inv.inviter || undefined,
            recipientEmail: inv.recipientEmail,
            recipientPhone: inv.recipientPhone,
            recipientName: inv.recipientName,
            status: inv.status,
            role: inv.role,
            channel: inv.channel,
            expiresAt: inv.expiresAt,
            acceptedAt: inv.acceptedAt,
            createdAt: inv.createdAt,
        };
    }
};
exports.InvitationsService = InvitationsService;
exports.InvitationsService = InvitationsService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService])
], InvitationsService);
//# sourceMappingURL=invitations.service.js.map