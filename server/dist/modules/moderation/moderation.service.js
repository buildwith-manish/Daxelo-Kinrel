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
exports.ModerationService = void 0;
const common_1 = require("@nestjs/common");
const prisma_service_1 = require("../../prisma/prisma.service");
const CLASSIFICATION_RULES = [
    {
        pattern: /\b(kill|murder|threat|weapon)\b/i,
        category: 'violence',
        action: 'quarantine',
        priority: 'urgent',
    },
    {
        pattern: /\b(nigger|chink|raghead)\b/i,
        category: 'hate_speech',
        action: 'reject',
        priority: 'critical',
    },
    {
        pattern: /\b(porn|nude|nsfw|sexual)\b/i,
        category: 'sexual_content',
        action: 'quarantine',
        priority: 'urgent',
    },
    {
        pattern: /\b(buy now|click here|free money|lottery winner)\b/i,
        category: 'spam',
        action: 'allow_with_flag',
        priority: 'low',
    },
    {
        pattern: /\b(aadhaar|pan card|credit card|ssn|social security)\b/i,
        category: 'pii_exposure',
        action: 'allow_with_flag',
        priority: 'high',
    },
    {
        pattern: /\b(caste|gotra superiority|untouchable)\b/i,
        category: 'caste_reference',
        action: 'allow_with_flag',
        priority: 'normal',
    },
];
let ModerationService = class ModerationService {
    constructor(prisma) {
        this.prisma = prisma;
    }
    async submitReport(userId, data) {
        const report = await this.prisma.contentReport.create({
            data: {
                reporterId: userId,
                targetType: data.targetType,
                targetId: data.targetId,
                reason: data.reason,
                description: data.description || null,
            },
        });
        const existingCase = await this.prisma.moderationCase.findFirst({
            where: {
                contentType: data.targetType,
                contentId: data.targetId,
                status: { in: ['pending', 'under_review'] },
            },
        });
        if (!existingCase) {
            await this.prisma.moderationCase.create({
                data: {
                    contentType: data.targetType,
                    contentId: data.targetId,
                    authorId: '',
                    source: 'user_report',
                    reporterId: userId,
                    reportReason: data.reason,
                    reportDetails: data.description,
                    status: 'pending',
                    priority: this.mapReportReasonToPriority(data.reason),
                },
            });
        }
        return {
            id: report.id,
            targetType: report.targetType,
            targetId: report.targetId,
            reason: report.reason,
            status: report.status,
            createdAt: report.createdAt,
        };
    }
    async getQueue(page = 1, limit = 20, filters) {
        const skip = (page - 1) * limit;
        const where = {};
        if (filters?.status)
            where.status = filters.status;
        else
            where.status = { in: ['pending', 'under_review'] };
        if (filters?.priority)
            where.priority = filters.priority;
        if (filters?.category)
            where.category = filters.category;
        const [cases, total] = await Promise.all([
            this.prisma.moderationCase.findMany({
                where,
                skip,
                take: limit,
                orderBy: [
                    { priority: 'desc' },
                    { createdAt: 'asc' },
                ],
                include: {
                    actions: { orderBy: { createdAt: 'desc' }, take: 5 },
                },
            }),
            this.prisma.moderationCase.count({ where }),
        ]);
        return {
            data: cases.map((c) => this.formatCase(c)),
            pagination: {
                page,
                limit,
                total,
                totalPages: Math.ceil(total / limit),
            },
        };
    }
    async classifyContent(adminId, data) {
        let matchedCategory = 'safe';
        let matchedAction = 'allow';
        let matchedPriority = 'normal';
        let confidence = 0.5;
        const flaggedCategories = [];
        for (const rule of CLASSIFICATION_RULES) {
            if (rule.pattern.test(data.contentPreview)) {
                matchedCategory = rule.category;
                matchedAction = rule.action;
                matchedPriority = rule.priority;
                confidence = 0.85;
                flaggedCategories.push(rule.category);
            }
        }
        const existingCase = await this.prisma.moderationCase.findFirst({
            where: {
                contentType: data.contentType,
                contentId: data.contentId,
                status: { in: ['pending', 'under_review'] },
            },
        });
        if (existingCase) {
            await this.prisma.moderationCase.update({
                where: { id: existingCase.id },
                data: {
                    category: matchedCategory,
                    autoAction: matchedAction,
                    confidence,
                    flaggedCategories: JSON.stringify(flaggedCategories),
                    priority: matchedPriority,
                    contentPreview: data.contentPreview.substring(0, 500),
                },
            });
            await this.prisma.moderationActionItem.create({
                data: {
                    caseId: existingCase.id,
                    actionType: 'auto_allow',
                    actorId: adminId,
                    details: JSON.stringify({
                        category: matchedCategory,
                        action: matchedAction,
                        confidence,
                    }),
                },
            });
            await this.prisma.moderationAuditLog.create({
                data: {
                    action: 'classify',
                    contentType: data.contentType,
                    contentId: data.contentId,
                    actorType: 'system',
                    actorId: adminId,
                    result: matchedAction,
                    reason: matchedCategory,
                    confidence,
                    metadata: JSON.stringify({ flaggedCategories }),
                },
            });
        }
        return {
            contentType: data.contentType,
            contentId: data.contentId,
            category: matchedCategory,
            autoAction: matchedAction,
            confidence,
            flaggedCategories,
            priority: matchedPriority,
        };
    }
    async listAppeals(page = 1, limit = 20, status) {
        const skip = (page - 1) * limit;
        const where = {};
        if (status)
            where.status = status;
        const [appeals, total] = await Promise.all([
            this.prisma.moderationAppeal.findMany({
                where,
                skip,
                take: limit,
                include: {
                    modCase: {
                        select: {
                            id: true,
                            contentType: true,
                            contentId: true,
                            category: true,
                            contentAction: true,
                        },
                    },
                    appellant: { select: { id: true, name: true, email: true } },
                },
                orderBy: { createdAt: 'desc' },
            }),
            this.prisma.moderationAppeal.count({ where }),
        ]);
        return {
            data: appeals.map((a) => ({
                id: a.id,
                caseId: a.caseId,
                appealReason: a.appealReason,
                appealTier: a.appealTier,
                status: a.status,
                reviewDecision: a.reviewDecision,
                reviewNotes: a.reviewNotes,
                appellant: a.appellant,
                modCase: a.modCase,
                createdAt: a.createdAt,
                reviewedAt: a.reviewedAt,
            })),
            pagination: {
                page,
                limit,
                total,
                totalPages: Math.ceil(total / limit),
            },
        };
    }
    async reviewAppeal(appealId, adminId, data) {
        const appeal = await this.prisma.moderationAppeal.findUnique({
            where: { id: appealId },
            include: { modCase: true },
        });
        if (!appeal) {
            throw new common_1.NotFoundException('Appeal not found');
        }
        if (appeal.status !== 'pending' && appeal.status !== 'under_review') {
            throw new common_1.BadRequestException(`Appeal is already ${appeal.status}`);
        }
        const validDecisions = ['upheld', 'reinstated', 'reduced', 'dismissed'];
        if (!validDecisions.includes(data.decision)) {
            throw new common_1.BadRequestException(`Invalid decision. Must be one of: ${validDecisions.join(', ')}`);
        }
        const updated = await this.prisma.moderationAppeal.update({
            where: { id: appealId },
            data: {
                status: data.decision === 'upheld' ? 'upheld' : data.decision,
                reviewerId: adminId,
                reviewedAt: new Date(),
                reviewDecision: data.decision,
                reviewNotes: data.notes || null,
            },
        });
        if (data.decision === 'reinstated' || data.decision === 'reduced') {
            await this.prisma.moderationCase.update({
                where: { id: appeal.caseId },
                data: {
                    status: 'actioned',
                    contentAction: data.decision === 'reinstated' ? 'none' : 'hidden',
                },
            });
        }
        else if (data.decision === 'upheld') {
            await this.prisma.moderationCase.update({
                where: { id: appeal.caseId },
                data: { status: 'actioned' },
            });
        }
        if (data.decision === 'dismissed' && appeal.appealTier === 1) {
        }
        return {
            id: updated.id,
            caseId: updated.caseId,
            appealTier: updated.appealTier,
            decision: updated.reviewDecision,
            notes: updated.reviewNotes,
            reviewedAt: updated.reviewedAt,
        };
    }
    mapReportReasonToPriority(reason) {
        const highPriorityReasons = ['hate_speech', 'violence', 'sexual_content', 'csam'];
        const urgentReasons = ['csam'];
        if (urgentReasons.includes(reason))
            return 'critical';
        if (highPriorityReasons.includes(reason))
            return 'urgent';
        if (reason === 'spam')
            return 'low';
        return 'normal';
    }
    formatCase(c) {
        return {
            id: c.id,
            contentType: c.contentType,
            contentId: c.contentId,
            contentPreview: c.contentPreview,
            authorId: c.authorId,
            category: c.category,
            confidence: c.confidence,
            autoAction: c.autoAction,
            flaggedCategories: JSON.parse(c.flaggedCategories || '[]'),
            status: c.status,
            priority: c.priority,
            source: c.source,
            reporterId: c.reporterId,
            reportReason: c.reportReason,
            contentAction: c.contentAction,
            reviewerId: c.reviewerId,
            reviewedAt: c.reviewedAt,
            actions: c.actions?.map((a) => ({
                id: a.id,
                actionType: a.actionType,
                actorId: a.actorId,
                details: a.details ? JSON.parse(a.details) : null,
                createdAt: a.createdAt,
            })),
            createdAt: c.createdAt,
            updatedAt: c.updatedAt,
        };
    }
};
exports.ModerationService = ModerationService;
exports.ModerationService = ModerationService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService])
], ModerationService);
//# sourceMappingURL=moderation.service.js.map