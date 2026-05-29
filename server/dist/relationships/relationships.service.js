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
exports.RelationshipsService = void 0;
const common_1 = require("@nestjs/common");
const prisma_service_1 = require("../prisma/prisma.service");
let RelationshipsService = class RelationshipsService {
    constructor(prisma) {
        this.prisma = prisma;
    }
    async listRelationships(userId, familyId) {
        const membership = await this.prisma.familyMember.findUnique({
            where: { familyId_userId: { familyId, userId } },
        });
        if (!membership) {
            throw new common_1.ForbiddenException('Not a member of this family');
        }
        const relationships = await this.prisma.relationship.findMany({
            where: { familyId, isActive: true },
            include: {
                fromPerson: true,
                toPerson: true,
            },
        });
        return relationships;
    }
    async createRelationship(userId, familyId, data) {
        const membership = await this.prisma.familyMember.findUnique({
            where: { familyId_userId: { familyId, userId } },
        });
        if (!membership) {
            throw new common_1.ForbiddenException('Not a member of this family');
        }
        const fromPerson = await this.prisma.person.findFirst({
            where: { id: data.fromPersonId, familyId, deletedAt: null },
        });
        const toPerson = await this.prisma.person.findFirst({
            where: { id: data.toPersonId, familyId, deletedAt: null },
        });
        if (!fromPerson || !toPerson) {
            throw new common_1.NotFoundException('One or both persons not found in this family');
        }
        const relationship = await this.prisma.relationship.create({
            data: {
                familyId,
                fromPersonId: data.fromPersonId,
                toPersonId: data.toPersonId,
                relationshipKey: data.relationshipKey || data.type || 'unknown',
                direction: data.direction || null,
                label: data.label || null,
            },
        });
        await this.prisma.family.update({
            where: { id: familyId },
            data: { lastActivityAt: new Date() },
        });
        return relationship;
    }
    async deleteRelationship(userId, relationshipId) {
        const relationship = await this.prisma.relationship.findUnique({
            where: { id: relationshipId },
        });
        if (!relationship) {
            throw new common_1.NotFoundException('Relationship not found');
        }
        const membership = await this.prisma.familyMember.findUnique({
            where: { familyId_userId: { familyId: relationship.familyId, userId } },
        });
        if (!membership) {
            throw new common_1.ForbiddenException('Not a member of this family');
        }
        await this.prisma.relationship.update({
            where: { id: relationshipId },
            data: { isActive: false },
        });
        return { message: 'Relationship deleted', id: relationshipId };
    }
};
exports.RelationshipsService = RelationshipsService;
exports.RelationshipsService = RelationshipsService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService])
], RelationshipsService);
//# sourceMappingURL=relationships.service.js.map