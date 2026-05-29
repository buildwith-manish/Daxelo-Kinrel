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
exports.PersonsService = void 0;
const common_1 = require("@nestjs/common");
const prisma_service_1 = require("../prisma/prisma.service");
let PersonsService = class PersonsService {
    constructor(prisma) {
        this.prisma = prisma;
    }
    async listPersons(userId, familyId) {
        const membership = await this.prisma.familyMember.findUnique({
            where: { familyId_userId: { familyId, userId } },
        });
        if (!membership) {
            throw new common_1.ForbiddenException('Not a member of this family');
        }
        const persons = await this.prisma.person.findMany({
            where: { familyId, deletedAt: null },
            orderBy: { createdAt: 'asc' },
        });
        return persons;
    }
    async addPerson(userId, familyId, data) {
        const membership = await this.prisma.familyMember.findUnique({
            where: { familyId_userId: { familyId, userId } },
        });
        if (!membership) {
            throw new common_1.ForbiddenException('Not a member of this family');
        }
        const person = await this.prisma.person.create({
            data: {
                name: data.name,
                familyId,
                gender: data.gender || null,
                birthYear: data.birthYear || null,
                isAnchor: data.isAnchor || false,
                generationIndex: data.generationIndex || null,
                city: data.city || null,
                gotra: data.gotra || null,
                isDeceased: data.isDeceased || false,
                privacyLevel: data.privacyLevel || 'public',
                occupation: data.occupation || null,
                notes: data.notes || null,
                sideOfFamily: data.sideOfFamily || null,
                photoUrl: data.photoUrl || null,
                dateOfBirth: data.dateOfBirth || null,
            },
        });
        const count = await this.prisma.person.count({
            where: { familyId, deletedAt: null },
        });
        await this.prisma.family.update({
            where: { id: familyId },
            data: { memberCount: count },
        });
        return person;
    }
    async updatePerson(userId, personId, data) {
        const person = await this.prisma.person.findUnique({
            where: { id: personId },
        });
        if (!person) {
            throw new common_1.NotFoundException('Person not found');
        }
        const membership = await this.prisma.familyMember.findUnique({
            where: { familyId_userId: { familyId: person.familyId, userId } },
        });
        if (!membership) {
            throw new common_1.ForbiddenException('Not a member of this family');
        }
        const allowedFields = [
            'name', 'gender', 'birthYear', 'isAnchor', 'generationIndex',
            'city', 'gotra', 'isDeceased', 'privacyLevel', 'occupation',
            'notes', 'sideOfFamily', 'photoUrl', 'dateOfBirth',
        ];
        const updateData = {};
        for (const field of allowedFields) {
            if (data[field] !== undefined) {
                updateData[field] = data[field];
            }
        }
        return this.prisma.person.update({
            where: { id: personId },
            data: updateData,
        });
    }
    async deletePerson(userId, personId) {
        const person = await this.prisma.person.findUnique({
            where: { id: personId },
        });
        if (!person) {
            throw new common_1.NotFoundException('Person not found');
        }
        const membership = await this.prisma.familyMember.findUnique({
            where: { familyId_userId: { familyId: person.familyId, userId } },
        });
        if (!membership) {
            throw new common_1.ForbiddenException('Not a member of this family');
        }
        const deleted = await this.prisma.person.update({
            where: { id: personId },
            data: { deletedAt: new Date() },
        });
        const count = await this.prisma.person.count({
            where: { familyId: person.familyId, deletedAt: null },
        });
        await this.prisma.family.update({
            where: { id: person.familyId },
            data: { memberCount: count },
        });
        return { message: 'Person deleted', id: personId };
    }
};
exports.PersonsService = PersonsService;
exports.PersonsService = PersonsService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService])
], PersonsService);
//# sourceMappingURL=persons.service.js.map