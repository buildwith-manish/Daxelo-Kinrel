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
var SyncService_1;
Object.defineProperty(exports, "__esModule", { value: true });
exports.SyncService = void 0;
const common_1 = require("@nestjs/common");
const prisma_service_1 = require("../../prisma/prisma.service");
let SyncService = SyncService_1 = class SyncService {
    constructor(prisma) {
        this.prisma = prisma;
        this.logger = new common_1.Logger(SyncService_1.name);
        this.MAX_RECORDS = 100;
        this.MAX_RESPONSE_SIZE_BYTES = 50 * 1024;
    }
    async sync(since, userId) {
        const sinceDate = since ? new Date(since) : new Date(0);
        if (since && isNaN(sinceDate.getTime())) {
            throw new common_1.BadRequestException('Invalid "since" timestamp. Must be a valid ISO 8601 date string.');
        }
        const memberships = await this.prisma.familyMember.findMany({
            where: { userId },
            select: { familyId: true },
        });
        const familyIds = memberships.map((m) => m.familyId);
        if (familyIds.length === 0) {
            return this.emptySyncResponse();
        }
        const members = await this.prisma.person.findMany({
            where: {
                familyId: { in: familyIds },
                updatedAt: { gt: sinceDate },
            },
            orderBy: { updatedAt: 'asc' },
            take: this.MAX_RECORDS,
            select: {
                id: true,
                familyId: true,
                name: true,
                gender: true,
                dateOfBirth: true,
                gotra: true,
                occupation: true,
                city: true,
                isDeceased: true,
                privacyLevel: true,
                deletedAt: true,
                birthYear: true,
                notes: true,
                sideOfFamily: true,
                generationIndex: true,
                isAnchor: true,
                photoUrl: true,
                username: true,
                updatedAt: true,
            },
        });
        const remainingCapacity = this.MAX_RECORDS - members.length;
        const events = remainingCapacity > 0
            ? await this.prisma.familyPost.findMany({
                where: {
                    familyId: { in: familyIds },
                    updatedAt: { gt: sinceDate },
                },
                orderBy: { updatedAt: 'asc' },
                take: remainingCapacity,
                select: {
                    id: true,
                    familyId: true,
                    authorId: true,
                    postType: true,
                    content: true,
                    reactions: true,
                    createdAt: true,
                    updatedAt: true,
                },
            })
            : [];
        const familyMetaArray = await this.prisma.family.findMany({
            where: {
                id: { in: familyIds },
                updatedAt: { gt: sinceDate },
            },
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
                avatarUrl: true,
                region: true,
                isOnboarded: true,
                updatedAt: true,
            },
        });
        const familyMeta = {};
        for (const f of familyMetaArray) {
            familyMeta[f.id] = f;
        }
        const serverTime = new Date().toISOString();
        const totalModified = members.length + events.length;
        const hasMore = totalModified >= this.MAX_RECORDS;
        const responsePayload = { members, events, familyMeta, serverTime, hasMore: false };
        const estimatedSize = JSON.stringify(responsePayload).length;
        if (estimatedSize > this.MAX_RESPONSE_SIZE_BYTES) {
            const truncatedMembers = this.truncateToFit(members, events, familyMeta, serverTime);
            return {
                members: truncatedMembers.members,
                events: truncatedMembers.events,
                familyMeta,
                serverTime,
                hasMore: true,
            };
        }
        return {
            members,
            events,
            familyMeta,
            serverTime,
            hasMore,
        };
    }
    truncateToFit(members, events, familyMeta, serverTime) {
        for (let i = members.length; i > 0; i--) {
            const payload = {
                members: members.slice(0, i),
                events: [],
                familyMeta,
                serverTime,
                hasMore: true,
            };
            if (JSON.stringify(payload).length <= this.MAX_RESPONSE_SIZE_BYTES) {
                let eventCount = 0;
                for (let j = 1; j <= events.length; j++) {
                    const testPayload = {
                        members: members.slice(0, i),
                        events: events.slice(0, j),
                        familyMeta,
                        serverTime,
                        hasMore: true,
                    };
                    if (JSON.stringify(testPayload).length <= this.MAX_RESPONSE_SIZE_BYTES) {
                        eventCount = j;
                    }
                    else {
                        break;
                    }
                }
                return {
                    members: members.slice(0, i),
                    events: events.slice(0, eventCount),
                };
            }
        }
        return { members: [], events: [] };
    }
    emptySyncResponse() {
        return {
            members: [],
            events: [],
            familyMeta: {},
            serverTime: new Date().toISOString(),
            hasMore: false,
        };
    }
};
exports.SyncService = SyncService;
exports.SyncService = SyncService = SyncService_1 = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService])
], SyncService);
//# sourceMappingURL=sync.service.js.map