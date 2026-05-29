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
exports.TimelineService = void 0;
const common_1 = require("@nestjs/common");
const prisma_service_1 = require("../../prisma/prisma.service");
let TimelineService = class TimelineService {
    constructor(prisma) {
        this.prisma = prisma;
    }
    async getTimeline(familyId, limit = 20, cursor) {
        const posts = await this.prisma.familyPost.findMany({
            where: { familyId },
            orderBy: { createdAt: 'desc' },
            take: limit + 1,
            skip: cursor ? 1 : 0,
            cursor: cursor ? { id: cursor } : undefined,
            select: {
                id: true,
                familyId: true,
                authorId: true,
                postType: true,
                content: true,
                reactions: true,
                createdAt: true,
                updatedAt: true,
                author: { select: { id: true, name: true, photoUrl: true } },
            },
        });
        const hasNextPage = posts.length > limit;
        const data = hasNextPage ? posts.slice(0, -1) : posts;
        const nextCursor = hasNextPage ? data[data.length - 1].id : null;
        return {
            data,
            nextCursor,
        };
    }
    async createPost(familyId, authorId, postType, content) {
        return this.prisma.familyPost.create({
            data: {
                familyId,
                authorId,
                postType,
                content: JSON.stringify(content),
            },
        });
    }
};
exports.TimelineService = TimelineService;
exports.TimelineService = TimelineService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService])
], TimelineService);
//# sourceMappingURL=timeline.service.js.map