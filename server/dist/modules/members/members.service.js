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
exports.MembersService = void 0;
const common_1 = require("@nestjs/common");
const prisma_service_1 = require("../../prisma/prisma.service");
const kinrel_gateway_1 = require("../gateway/kinrel.gateway");
const ROLE_HIERARCHY = {
    viewer: 1,
    member: 2,
    editor: 3,
    admin: 4,
};
let MembersService = class MembersService {
    constructor(prisma, gateway) {
        this.prisma = prisma;
        this.gateway = gateway;
    }
    async create(userId, familyId, dto) {
        await this.requireFamilyRole(userId, familyId, 'member');
        if (!dto.name || typeof dto.name !== 'string' || dto.name.trim().length === 0) {
            throw new common_1.BadRequestException('Person name is required');
        }
        const person = await this.prisma.$transaction(async (tx) => {
            const created = await tx.person.create({
                data: {
                    familyId,
                    name: dto.name.trim(),
                    gender: dto.gender || null,
                    dateOfBirth: dto.dateOfBirth ? new Date(dto.dateOfBirth) : null,
                    city: dto.city?.trim() || null,
                    gotra: dto.gotra?.trim() || null,
                    birthYear: dto.birthYear || null,
                    isAnchor: dto.isAnchor ?? false,
                    sideOfFamily: dto.sideOfFamily || null,
                    generationIndex: dto.generationIndex ?? 0,
                    privacyLevel: 'family',
                },
            });
            await tx.family.update({
                where: { id: familyId },
                data: {
                    memberCount: { increment: 1 },
                    lastActivityAt: new Date(),
                },
            });
            if (dto.isAnchor) {
                await tx.family.update({
                    where: { id: familyId },
                    data: { anchorPersonId: created.id },
                });
            }
            return created;
        });
        this.gateway.emitToFamily(familyId, 'person:created', {
            id: person.id,
            updatedAt: (person.updatedAt ?? new Date()).toISOString(),
            type: 'person:created',
            familyId,
        });
        return this.formatPerson(person);
    }
    async findAll(userId, familyId, query) {
        await this.requireFamilyMember(userId, familyId);
        const limit = Math.min(100, Math.max(1, query.limit || 50));
        const where = {
            familyId,
            deletedAt: null,
        };
        if (query.search) {
            where.name = { contains: query.search };
        }
        const sortField = query.sort || 'createdAt';
        const sortOrder = query.order?.toLowerCase() === 'asc' ? 'asc' : 'desc';
        const orderBy = { [sortField]: sortOrder };
        const includeRelationships = query.includeRelationships === 'true';
        const listSelect = {
            id: true,
            familyId: true,
            name: true,
            gender: true,
            dateOfBirth: true,
            city: true,
            gotra: true,
            isDeceased: true,
            deletedAt: true,
            birthYear: true,
            occupation: true,
            privacyLevel: true,
            notes: true,
            sideOfFamily: true,
            generationIndex: true,
            isAnchor: true,
            photoUrl: true,
            username: true,
            updatedAt: true,
        };
        const persons = includeRelationships
            ? await this.prisma.person.findMany({
                where,
                take: limit + 1,
                skip: query.cursor ? 1 : 0,
                cursor: query.cursor ? { id: query.cursor } : undefined,
                orderBy,
                include: {
                    relationshipsFrom: {
                        where: { isActive: true, toPerson: { deletedAt: null } },
                        include: { toPerson: { select: { id: true } } },
                    },
                    relationshipsTo: {
                        where: { isActive: true, fromPerson: { deletedAt: null } },
                        include: { fromPerson: { select: { id: true } } },
                    },
                },
            })
            : await this.prisma.person.findMany({
                where,
                take: limit + 1,
                skip: query.cursor ? 1 : 0,
                cursor: query.cursor ? { id: query.cursor } : undefined,
                orderBy,
                select: listSelect,
            });
        const hasNextPage = persons.length > limit;
        const data = hasNextPage ? persons.slice(0, -1) : persons;
        const nextCursor = hasNextPage ? data[data.length - 1].id : null;
        return {
            data: data.map((p) => this.formatPerson(p)),
            nextCursor,
        };
    }
    async findOne(userId, familyId, personId) {
        await this.requireFamilyMember(userId, familyId);
        const person = await this.prisma.person.findFirst({
            where: { id: personId, familyId, deletedAt: null },
            include: {
                relationshipsFrom: {
                    where: { isActive: true, toPerson: { deletedAt: null } },
                    include: { toPerson: { select: { id: true } } },
                },
                relationshipsTo: {
                    where: { isActive: true, fromPerson: { deletedAt: null } },
                    include: { fromPerson: { select: { id: true } } },
                },
            },
        });
        if (!person) {
            throw new common_1.NotFoundException('Person not found');
        }
        return this.formatPerson(person);
    }
    async update(userId, familyId, personId, dto) {
        await this.requireFamilyRole(userId, familyId, 'editor');
        const existing = await this.prisma.person.findFirst({
            where: { id: personId, familyId, deletedAt: null },
        });
        if (!existing) {
            throw new common_1.NotFoundException('Person not found');
        }
        const updateData = {};
        if (dto.name !== undefined)
            updateData.name = dto.name.trim();
        if (dto.gender !== undefined)
            updateData.gender = dto.gender || null;
        if (dto.dateOfBirth !== undefined)
            updateData.dateOfBirth = dto.dateOfBirth ? new Date(dto.dateOfBirth) : null;
        if (dto.city !== undefined)
            updateData.city = dto.city?.trim() || null;
        if (dto.gotra !== undefined)
            updateData.gotra = dto.gotra?.trim() || null;
        if (dto.birthYear !== undefined)
            updateData.birthYear = dto.birthYear || null;
        if (dto.isDeceased !== undefined)
            updateData.isDeceased = dto.isDeceased;
        if (dto.occupation !== undefined)
            updateData.occupation = dto.occupation?.trim() || null;
        if (dto.privacyLevel !== undefined)
            updateData.privacyLevel = dto.privacyLevel;
        if (dto.notes !== undefined)
            updateData.notes = dto.notes?.trim() || null;
        if (dto.sideOfFamily !== undefined)
            updateData.sideOfFamily = dto.sideOfFamily || null;
        if (dto.generationIndex !== undefined)
            updateData.generationIndex = dto.generationIndex;
        if (dto.isAnchor !== undefined)
            updateData.isAnchor = dto.isAnchor;
        if (dto.photoUrl !== undefined)
            updateData.photoUrl = dto.photoUrl;
        if (dto.username !== undefined)
            updateData.username = dto.username?.trim() || null;
        const updated = await this.prisma.person.update({
            where: { id: personId },
            data: updateData,
        });
        if (dto.isAnchor === true) {
            await this.prisma.family.update({
                where: { id: familyId },
                data: { anchorPersonId: personId, lastActivityAt: new Date() },
            });
        }
        this.gateway.emitToFamily(familyId, 'person:updated', {
            id: personId,
            updatedAt: (updated.updatedAt ?? new Date()).toISOString(),
            type: 'person:updated',
            familyId,
        });
        return this.formatPerson(updated);
    }
    async remove(userId, familyId, personId) {
        await this.requireFamilyRole(userId, familyId, 'editor');
        const existing = await this.prisma.person.findFirst({
            where: { id: personId, familyId, deletedAt: null },
        });
        if (!existing) {
            throw new common_1.NotFoundException('Person not found');
        }
        await this.prisma.$transaction(async (tx) => {
            await tx.person.update({
                where: { id: personId },
                data: { deletedAt: new Date() },
            });
            await tx.relationship.updateMany({
                where: {
                    OR: [{ fromPersonId: personId }, { toPersonId: personId }],
                },
                data: { isActive: false },
            });
            await tx.family.update({
                where: { id: familyId },
                data: {
                    memberCount: { decrement: 1 },
                    lastActivityAt: new Date(),
                },
            });
        });
        this.gateway.emitToFamily(familyId, 'person:deleted', {
            id: personId,
            updatedAt: new Date().toISOString(),
            type: 'person:deleted',
            familyId,
        });
        this.gateway.emitToFamily(familyId, 'graph:updated', {
            id: familyId,
            updatedAt: new Date().toISOString(),
            type: 'graph:updated',
            familyId,
        });
        return { deleted: true, personId };
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
    formatPerson(person) {
        const result = {
            id: person.id,
            familyId: person.familyId,
            name: person.name,
            gender: person.gender ?? null,
            dateOfBirth: person.dateOfBirth ?? null,
            city: person.city ?? null,
            gotra: person.gotra ?? null,
            isDeceased: person.isDeceased ?? false,
            deletedAt: person.deletedAt ?? null,
            birthYear: person.birthYear ?? null,
            occupation: person.occupation ?? null,
            privacyLevel: person.privacyLevel ?? 'family',
            notes: person.notes ?? null,
            sideOfFamily: person.sideOfFamily ?? null,
            generationIndex: person.generationIndex ?? 0,
            isAnchor: person.isAnchor ?? false,
            photoUrl: person.photoUrl ?? null,
            username: person.username ?? null,
        };
        if (person.relationshipsFrom || person.relationshipsTo) {
            const relationships = [];
            if (person.relationshipsFrom) {
                for (const rel of person.relationshipsFrom) {
                    if (rel.toPerson) {
                        relationships.push({
                            id: rel.id,
                            familyId: rel.familyId,
                            fromPersonId: rel.fromPersonId,
                            toPersonId: rel.toPersonId,
                            relationshipKey: rel.relationshipKey,
                            direction: rel.direction,
                            isActive: rel.isActive,
                            label: rel.label ?? null,
                        });
                    }
                }
            }
            if (person.relationshipsTo) {
                for (const rel of person.relationshipsTo) {
                    if (rel.fromPerson) {
                        relationships.push({
                            id: rel.id,
                            familyId: rel.familyId,
                            fromPersonId: rel.fromPersonId,
                            toPersonId: rel.toPersonId,
                            relationshipKey: rel.relationshipKey,
                            direction: rel.direction,
                            isActive: rel.isActive,
                            label: rel.label ?? null,
                        });
                    }
                }
            }
            result.relationships = relationships;
        }
        return result;
    }
};
exports.MembersService = MembersService;
exports.MembersService = MembersService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService,
        kinrel_gateway_1.KinrelGateway])
], MembersService);
//# sourceMappingURL=members.service.js.map