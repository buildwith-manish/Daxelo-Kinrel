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
exports.ShareService = void 0;
const common_1 = require("@nestjs/common");
const prisma_service_1 = require("../../prisma/prisma.service");
const crypto_1 = require("crypto");
const VALID_CARD_TYPES = [
    'family_tree',
    'birthday',
    'anniversary',
    'memorial',
    'milestone',
    'relationship_discovery',
    'festival_greeting',
];
let ShareService = class ShareService {
    constructor(prisma) {
        this.prisma = prisma;
    }
    async createShareableLink(userId, data) {
        if (!VALID_CARD_TYPES.includes(data.cardType)) {
            throw new common_1.BadRequestException(`Invalid card type. Must be one of: ${VALID_CARD_TYPES.join(', ')}`);
        }
        if (!data.title || data.title.trim().length === 0) {
            throw new common_1.BadRequestException('Title is required');
        }
        const token = (0, crypto_1.randomBytes)(16).toString('hex');
        let expiresAt = null;
        if (data.expiresInDays && data.expiresInDays > 0) {
            expiresAt = new Date();
            expiresAt.setDate(expiresAt.getDate() + data.expiresInDays);
        }
        const deepLinkUrl = data.deepLinkUrl ||
            `kinrel://share/${data.cardType}/${token}`;
        const link = await this.prisma.shareableLink.create({
            data: {
                token,
                cardType: data.cardType,
                familyId: data.familyId || null,
                personId: data.personId || null,
                title: data.title.trim(),
                description: data.description?.trim() || '',
                deepLinkUrl,
                expiresAt,
            },
        });
        return {
            id: link.id,
            token: link.token,
            cardType: link.cardType,
            familyId: link.familyId,
            personId: link.personId,
            title: link.title,
            description: link.description,
            deepLinkUrl: link.deepLinkUrl,
            viewCount: link.viewCount,
            shareCount: link.shareCount,
            expiresAt: link.expiresAt,
            createdAt: link.createdAt,
        };
    }
    async getShareStats(token) {
        const link = await this.prisma.shareableLink.findUnique({
            where: { token },
        });
        if (!link) {
            throw new common_1.NotFoundException('Shareable link not found');
        }
        return {
            id: link.id,
            token: link.token,
            cardType: link.cardType,
            title: link.title,
            viewCount: link.viewCount,
            shareCount: link.shareCount,
            expiresAt: link.expiresAt,
            createdAt: link.createdAt,
        };
    }
    async getSharedCard(token) {
        const link = await this.prisma.shareableLink.findUnique({
            where: { token },
        });
        if (!link) {
            throw new common_1.NotFoundException('Shared card not found or has expired');
        }
        if (link.expiresAt && link.expiresAt < new Date()) {
            throw new common_1.NotFoundException('Shared card has expired');
        }
        await this.prisma.shareableLink.update({
            where: { token },
            data: { viewCount: { increment: 1 } },
        });
        let familyData = null;
        let personData = null;
        if (link.familyId) {
            const family = await this.prisma.family.findUnique({
                where: { id: link.familyId },
                select: {
                    id: true,
                    name: true,
                    description: true,
                    avatarUrl: true,
                    memberCount: true,
                    gotra: true,
                    originVillage: true,
                    region: true,
                },
            });
            familyData = family;
        }
        if (link.personId) {
            const person = await this.prisma.person.findUnique({
                where: { id: link.personId },
                select: {
                    id: true,
                    name: true,
                    dateOfBirth: true,
                    birthYear: true,
                    photoUrl: true,
                    gender: true,
                    gotra: true,
                    occupation: true,
                    city: true,
                },
            });
            personData = person;
        }
        return {
            id: link.id,
            token: link.token,
            cardType: link.cardType,
            title: link.title,
            description: link.description,
            deepLinkUrl: link.deepLinkUrl,
            viewCount: link.viewCount + 1,
            shareCount: link.shareCount,
            family: familyData,
            person: personData,
            expiresAt: link.expiresAt,
            createdAt: link.createdAt,
        };
    }
};
exports.ShareService = ShareService;
exports.ShareService = ShareService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService])
], ShareService);
//# sourceMappingURL=share.service.js.map