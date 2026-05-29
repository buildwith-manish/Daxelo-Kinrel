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
exports.getInverseKey = getInverseKey;
const common_1 = require("@nestjs/common");
const prisma_service_1 = require("../../prisma/prisma.service");
const kinrel_gateway_1 = require("../gateway/kinrel.gateway");
const ROLE_HIERARCHY = {
    viewer: 1,
    member: 2,
    editor: 3,
    admin: 4,
};
const INVERSE_RELATIONSHIP_MAP = {
    father: (toGender) => toGender === 'female' ? 'daughter' : 'son',
    mother: (toGender) => toGender === 'female' ? 'daughter' : 'son',
    son: () => 'father',
    daughter: () => 'mother',
    husband: () => 'wife',
    wife: () => 'husband',
    brother: (toGender) => toGender === 'female' ? 'sister' : 'brother',
    sister: (toGender) => toGender === 'female' ? 'sister' : 'brother',
    grandfather: (toGender) => toGender === 'female' ? 'granddaughter' : 'grandson',
    grandmother: (toGender) => toGender === 'female' ? 'granddaughter' : 'grandson',
    grandson: () => 'grandfather',
    granddaughter: () => 'grandmother',
    uncle: (toGender) => toGender === 'female' ? 'niece' : 'nephew',
    aunt: (toGender) => toGender === 'female' ? 'niece' : 'nephew',
    nephew: () => 'uncle',
    niece: () => 'aunt',
    paternal_grandfather: (toGender) => toGender === 'female' ? 'granddaughter' : 'grandson',
    paternal_grandmother: (toGender) => toGender === 'female' ? 'granddaughter' : 'grandson',
    maternal_grandfather: (toGender) => toGender === 'female' ? 'granddaughter' : 'grandson',
    maternal_grandmother: (toGender) => toGender === 'female' ? 'granddaughter' : 'grandson',
    husbands_father: () => 'sons_wife',
    husbands_mother: () => 'sons_wife',
    wives_father: () => 'daughters_husband',
    wives_mother: () => 'daughters_husband',
    sons_wife: () => 'husbands_father',
    daughters_husband: () => 'wives_father',
    elder_brother: () => 'younger_brother',
    younger_brother: () => 'elder_brother',
    elder_sister: () => 'younger_sister',
    younger_sister: () => 'elder_sister',
    cousin: () => 'cousin',
    father_in_law: (toGender) => toGender === 'female' ? 'daughters_husband' : 'sons_wife',
    mother_in_law: (toGender) => toGender === 'female' ? 'daughters_husband' : 'sons_wife',
    brother_in_law: () => 'brother_in_law',
    sister_in_law: () => 'sister_in_law',
};
function getInverseKey(forwardKey, toGender) {
    const mapper = INVERSE_RELATIONSHIP_MAP[forwardKey];
    if (mapper) {
        return mapper(toGender);
    }
    return forwardKey;
}
let RelationshipsService = class RelationshipsService {
    constructor(prisma, gateway) {
        this.prisma = prisma;
        this.gateway = gateway;
    }
    async create(userId, familyId, dto) {
        await this.requireFamilyRole(userId, familyId, 'editor');
        if (dto.fromPersonId === dto.toPersonId) {
            throw new common_1.BadRequestException('Cannot create a self-relationship');
        }
        const [fromPerson, toPerson] = await Promise.all([
            this.prisma.person.findFirst({
                where: { id: dto.fromPersonId, familyId, deletedAt: null },
            }),
            this.prisma.person.findFirst({
                where: { id: dto.toPersonId, familyId, deletedAt: null },
            }),
        ]);
        if (!fromPerson) {
            throw new common_1.NotFoundException('Source person not found in this family');
        }
        if (!toPerson) {
            throw new common_1.NotFoundException('Target person not found in this family');
        }
        const existingForward = await this.prisma.relationship.findFirst({
            where: {
                familyId,
                fromPersonId: dto.fromPersonId,
                toPersonId: dto.toPersonId,
                relationshipKey: dto.relationshipKey,
            },
        });
        if (existingForward) {
            throw new common_1.ConflictException('This relationship already exists');
        }
        const inverseKey = getInverseKey(dto.relationshipKey, toPerson.gender);
        const result = await this.prisma.$transaction(async (tx) => {
            const forward = await tx.relationship.create({
                data: {
                    familyId,
                    fromPersonId: dto.fromPersonId,
                    toPersonId: dto.toPersonId,
                    relationshipKey: dto.relationshipKey,
                    direction: 'from',
                    isActive: true,
                },
            });
            await tx.relationship.create({
                data: {
                    familyId,
                    fromPersonId: dto.toPersonId,
                    toPersonId: dto.fromPersonId,
                    relationshipKey: inverseKey,
                    direction: 'from',
                    isActive: true,
                },
            });
            await tx.family.update({
                where: { id: familyId },
                data: { lastActivityAt: new Date() },
            });
            return forward;
        });
        this.gateway.emitToFamily(familyId, 'relationship:created', {
            id: result.id,
            updatedAt: (result.updatedAt ?? new Date()).toISOString(),
            type: 'relationship:created',
            familyId,
        });
        this.gateway.emitToFamily(familyId, 'graph:updated', {
            id: familyId,
            updatedAt: new Date().toISOString(),
            type: 'graph:updated',
            familyId,
        });
        return this.formatRelationship(result);
    }
    async findAll(userId, familyId, query) {
        await this.requireFamilyMember(userId, familyId);
        const where = {
            familyId,
            isActive: true,
            fromPerson: { deletedAt: null },
            toPerson: { deletedAt: null },
        };
        if (query.personId) {
            delete where.fromPerson;
            delete where.toPerson;
            where.OR = [
                { fromPersonId: query.personId, fromPerson: { deletedAt: null }, toPerson: { deletedAt: null }, isActive: true },
                { toPersonId: query.personId, fromPerson: { deletedAt: null }, toPerson: { deletedAt: null }, isActive: true },
            ];
        }
        const relationships = await this.prisma.relationship.findMany({
            where,
            orderBy: { createdAt: 'desc' },
            include: {
                fromPerson: { select: { id: true, deletedAt: true } },
                toPerson: { select: { id: true, deletedAt: true } },
            },
        });
        return relationships
            .filter((r) => r.fromPerson && r.toPerson)
            .map((r) => this.formatRelationship(r));
    }
    async remove(userId, familyId, relationshipId) {
        await this.requireFamilyRole(userId, familyId, 'editor');
        const relationship = await this.prisma.relationship.findFirst({
            where: { id: relationshipId, familyId },
        });
        if (!relationship) {
            throw new common_1.NotFoundException('Relationship not found');
        }
        const inverseKey = getInverseKey(relationship.relationshipKey);
        const inverse = await this.prisma.relationship.findFirst({
            where: {
                familyId,
                fromPersonId: relationship.toPersonId,
                toPersonId: relationship.fromPersonId,
                relationshipKey: inverseKey,
                isActive: true,
            },
        });
        await this.prisma.$transaction(async (tx) => {
            await tx.relationship.delete({ where: { id: relationshipId } });
            if (inverse) {
                await tx.relationship.delete({ where: { id: inverse.id } });
            }
            await tx.family.update({
                where: { id: familyId },
                data: { lastActivityAt: new Date() },
            });
        });
        this.gateway.emitToFamily(familyId, 'relationship:deleted', {
            id: relationshipId,
            updatedAt: new Date().toISOString(),
            type: 'relationship:deleted',
            familyId,
        });
        this.gateway.emitToFamily(familyId, 'graph:updated', {
            id: familyId,
            updatedAt: new Date().toISOString(),
            type: 'graph:updated',
            familyId,
        });
        return { deleted: true, relationshipId };
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
    formatRelationship(rel) {
        return {
            id: rel.id,
            familyId: rel.familyId,
            fromPersonId: rel.fromPersonId,
            toPersonId: rel.toPersonId,
            relationshipKey: rel.relationshipKey,
            direction: rel.direction,
            isActive: rel.isActive,
            label: rel.label ?? null,
        };
    }
};
exports.RelationshipsService = RelationshipsService;
exports.RelationshipsService = RelationshipsService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        kinrel_gateway_1.KinrelGateway])
], RelationshipsService);
//# sourceMappingURL=relationships.service.js.map