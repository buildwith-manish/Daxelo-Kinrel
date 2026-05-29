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
const prisma_service_1 = require("../prisma/prisma.service");
let InvitationsService = class InvitationsService {
    constructor(prisma) {
        this.prisma = prisma;
    }
    async acceptInvitation(userId, invitationId) {
        const invitation = await this.prisma.invitation.findUnique({
            where: { id: invitationId },
        });
        if (!invitation) {
            throw new common_1.NotFoundException('Invitation not found');
        }
        if (invitation.inviterId !== userId) {
            throw new common_1.ForbiddenException('This invitation is not for you');
        }
        if (invitation.status !== 'pending') {
            return { message: 'Invitation already processed', invitation };
        }
        const updated = await this.prisma.invitation.update({
            where: { id: invitationId },
            data: { status: 'accepted' },
        });
        await this.prisma.familyMember.create({
            data: {
                familyId: invitation.familyId,
                userId,
                role: invitation.role,
            },
        });
        const count = await this.prisma.familyMember.count({
            where: { familyId: invitation.familyId },
        });
        await this.prisma.family.update({
            where: { id: invitation.familyId },
            data: { memberCount: count },
        });
        return { message: 'Invitation accepted', invitation: updated };
    }
    async declineInvitation(userId, invitationId) {
        const invitation = await this.prisma.invitation.findUnique({
            where: { id: invitationId },
        });
        if (!invitation) {
            throw new common_1.NotFoundException('Invitation not found');
        }
        if (invitation.inviterId !== userId) {
            throw new common_1.ForbiddenException('This invitation is not for you');
        }
        const updated = await this.prisma.invitation.update({
            where: { id: invitationId },
            data: { status: 'declined' },
        });
        return { message: 'Invitation declined', invitation: updated };
    }
};
exports.InvitationsService = InvitationsService;
exports.InvitationsService = InvitationsService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService])
], InvitationsService);
//# sourceMappingURL=invitations.service.js.map