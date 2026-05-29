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
exports.AdminService = void 0;
const common_1 = require("@nestjs/common");
const prisma_service_1 = require("../../prisma/prisma.service");
let AdminService = class AdminService {
    constructor(prisma) {
        this.prisma = prisma;
    }
    requireAdmin(userRole) {
        if (userRole !== 'admin') {
            throw new common_1.ForbiddenException('Admin access required');
        }
    }
    async getDashboardStats(userRole) {
        this.requireAdmin(userRole);
        const [totalUsers, totalFamilies, totalPersons, openTickets, totalTickets, totalInvitations, totalCommunities, totalApiKeys, whatsappOptedIn,] = await Promise.all([
            this.prisma.user.count(),
            this.prisma.family.count(),
            this.prisma.person.count({ where: { deletedAt: null } }),
            this.prisma.supportTicket.count({
                where: { status: { in: ['open', 'in_progress'] } },
            }),
            this.prisma.supportTicket.count(),
            this.prisma.invitation.count({ where: { status: 'pending' } }),
            this.prisma.community.count(),
            this.prisma.apiKey.count({ where: { revokedAt: null } }),
            this.prisma.whatsAppConsent.count({ where: { optedIn: true } }),
        ]);
        const thirtyDaysAgo = new Date();
        thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
        const newUsersLast30Days = await this.prisma.user.count({
            where: { createdAt: { gte: thirtyDaysAgo } },
        });
        const resolvedTicketsLast30Days = await this.prisma.supportTicket.count({
            where: {
                status: { in: ['resolved', 'closed'] },
                resolvedAt: { gte: thirtyDaysAgo },
            },
        });
        const slaBreachCount = await this.prisma.supportTicket.count({
            where: { slaBreached: true },
        });
        return {
            users: {
                total: totalUsers,
                newLast30Days: newUsersLast30Days,
            },
            families: {
                total: totalFamilies,
            },
            persons: {
                total: totalPersons,
            },
            support: {
                openTickets,
                totalTickets,
                resolvedLast30Days: resolvedTicketsLast30Days,
                slaBreachCount,
            },
            invitations: {
                pending: totalInvitations,
            },
            communities: {
                total: totalCommunities,
            },
            developer: {
                activeApiKeys: totalApiKeys,
            },
            whatsapp: {
                optedIn: whatsappOptedIn,
            },
        };
    }
    async listUsers(userRole, page = 1, limit = 20, search) {
        this.requireAdmin(userRole);
        const skip = (page - 1) * limit;
        const where = {};
        if (search) {
            where.OR = [
                { email: { contains: search } },
                { name: { contains: search } },
                { username: { contains: search } },
                { phone: { contains: search } },
            ];
        }
        const [users, total] = await Promise.all([
            this.prisma.user.findMany({
                where,
                skip,
                take: limit,
                select: {
                    id: true,
                    email: true,
                    name: true,
                    username: true,
                    role: true,
                    phone: true,
                    twoFactorEnabled: true,
                    preferredLanguage: true,
                    createdAt: true,
                    updatedAt: true,
                    subscription: {
                        select: {
                            plan: true,
                            status: true,
                            supportTier: true,
                        },
                    },
                    _count: {
                        select: {
                            families: true,
                            supportTickets: true,
                            sentInvitations: true,
                        },
                    },
                },
                orderBy: { createdAt: 'desc' },
            }),
            this.prisma.user.count({ where }),
        ]);
        return {
            data: users.map((u) => ({
                id: u.id,
                email: u.email,
                name: u.name,
                username: u.username,
                role: u.role,
                phone: u.phone,
                twoFactorEnabled: u.twoFactorEnabled,
                preferredLanguage: u.preferredLanguage,
                subscription: u.subscription,
                familyCount: u._count.families,
                ticketCount: u._count.supportTickets,
                invitationCount: u._count.sentInvitations,
                createdAt: u.createdAt,
                updatedAt: u.updatedAt,
            })),
            pagination: {
                page,
                limit,
                total,
                totalPages: Math.ceil(total / limit),
            },
        };
    }
    async getSlaReport(userRole) {
        this.requireAdmin(userRole);
        const [totalTickets, breachedTickets, avgFirstResponseTime, avgResolutionTime, csatRatings,] = await Promise.all([
            this.prisma.supportTicket.count(),
            this.prisma.supportTicket.count({
                where: { slaBreached: true },
            }),
            this.prisma.supportAgent.aggregate({
                _avg: { avgResponseTime: true },
            }),
            this.prisma.supportAgent.aggregate({
                _avg: { avgResolutionTime: true },
            }),
            this.prisma.supportCSAT.aggregate({
                _avg: { rating: true },
                _count: { rating: true },
            }),
        ]);
        const breachByTier = await this.prisma.supportTicket.groupBy({
            by: ['slaTier'],
            where: { slaBreached: true },
            _count: { id: true },
        });
        const totalByTier = await this.prisma.supportTicket.groupBy({
            by: ['slaTier'],
            _count: { id: true },
        });
        const tierReport = {};
        for (const item of totalByTier) {
            const tier = item.slaTier;
            const totalForTier = item._count.id;
            const breachedForTier = breachByTier.find((b) => b.slaTier === tier)?._count.id || 0;
            tierReport[tier] = {
                total: totalForTier,
                breached: breachedForTier,
                breachRate: totalForTier > 0 ? Math.round((breachedForTier / totalForTier) * 100) : 0,
            };
        }
        return {
            overall: {
                totalTickets,
                breachedTickets,
                breachRate: totalTickets > 0
                    ? Math.round((breachedTickets / totalTickets) * 100)
                    : 0,
                avgFirstResponseTimeMinutes: avgFirstResponseTime._avg.avgResponseTime || 0,
                avgResolutionTimeMinutes: avgResolutionTime._avg.avgResolutionTime || 0,
                avgCsatScore: csatRatings._avg.rating
                    ? Math.round(csatRatings._avg.rating * 100) / 100
                    : 0,
                totalCsatResponses: csatRatings._count.rating,
            },
            byTier: tierReport,
        };
    }
    async getKbAnalytics(userRole) {
        this.requireAdmin(userRole);
        const [totalArticles, publishedArticles, totalViews, totalSearches, topArticles,] = await Promise.all([
            this.prisma.kBArticle.count(),
            this.prisma.kBArticle.count({ where: { status: 'published' } }),
            this.prisma.kBArticle.aggregate({ _sum: { views: true } }),
            this.prisma.kBSearchLog.count(),
            this.prisma.kBArticle.findMany({
                where: { status: 'published' },
                orderBy: { views: 'desc' },
                take: 10,
                select: {
                    id: true,
                    slug: true,
                    title: true,
                    views: true,
                    helpfulYes: true,
                    helpfulNo: true,
                    category: true,
                },
            }),
        ]);
        const searchesLeadingToTickets = await this.prisma.kBSearchLog.count({
            where: { ledToTicket: true },
        });
        return {
            totalArticles,
            publishedArticles,
            totalViews: totalViews._sum.views || 0,
            totalSearches,
            searchesLeadingToTickets,
            searchToTicketRate: totalSearches > 0
                ? Math.round((searchesLeadingToTickets / totalSearches) * 100)
                : 0,
            topArticles: topArticles.map((a) => ({
                id: a.id,
                slug: a.slug,
                title: a.title,
                category: a.category,
                views: a.views,
                helpfulYes: a.helpfulYes,
                helpfulNo: a.helpfulNo,
                helpfulness: a.helpfulYes + a.helpfulNo > 0
                    ? Math.round((a.helpfulYes / (a.helpfulYes + a.helpfulNo)) * 100)
                    : 0,
            })),
        };
    }
    async getWhatsappTemplates(userRole) {
        this.requireAdmin(userRole);
        const templates = await this.prisma.whatsAppTemplate.findMany({
            orderBy: { createdAt: 'desc' },
        });
        return templates.map((t) => ({
            id: t.id,
            name: t.name,
            category: t.category,
            status: t.status,
            whatsappId: t.whatsappId,
            languages: JSON.parse(t.languages || '[]'),
            rejectionReason: t.rejectionReason,
            lastSyncedAt: t.lastSyncedAt,
            createdAt: t.createdAt,
            updatedAt: t.updatedAt,
        }));
    }
    async getModerationStats(userRole) {
        this.requireAdmin(userRole);
        const [pendingCases, underReviewCases, actionedCases, totalReports, pendingReports, pendingAppeals, totalAppeals,] = await Promise.all([
            this.prisma.moderationCase.count({ where: { status: 'pending' } }),
            this.prisma.moderationCase.count({ where: { status: 'under_review' } }),
            this.prisma.moderationCase.count({ where: { status: 'actioned' } }),
            this.prisma.contentReport.count(),
            this.prisma.contentReport.count({ where: { status: 'pending' } }),
            this.prisma.moderationAppeal.count({ where: { status: 'pending' } }),
            this.prisma.moderationAppeal.count(),
        ]);
        const casesByCategory = await this.prisma.moderationCase.groupBy({
            by: ['category'],
            _count: { id: true },
        });
        const reportsByReason = await this.prisma.contentReport.groupBy({
            by: ['reason'],
            _count: { id: true },
        });
        return {
            cases: {
                pending: pendingCases,
                underReview: underReviewCases,
                actioned: actionedCases,
            },
            reports: {
                total: totalReports,
                pending: pendingReports,
            },
            appeals: {
                total: totalAppeals,
                pending: pendingAppeals,
            },
            casesByCategory: casesByCategory.map((c) => ({
                category: c.category,
                count: c._count.id,
            })),
            reportsByReason: reportsByReason.map((r) => ({
                reason: r.reason,
                count: r._count.id,
            })),
        };
    }
    async getModerationRules(userRole) {
        this.requireAdmin(userRole);
        const rules = await this.prisma.moderationRule.findMany({
            where: { isActive: true },
            orderBy: { createdAt: 'desc' },
        });
        return rules.map((r) => ({
            id: r.id,
            name: r.name,
            description: r.description,
            contentType: r.contentType,
            category: r.category,
            condition: r.condition,
            action: r.action,
            priority: r.priority,
            isActive: r.isActive,
            createdBy: r.createdBy,
            createdAt: r.createdAt,
            updatedAt: r.updatedAt,
        }));
    }
};
exports.AdminService = AdminService;
exports.AdminService = AdminService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService])
], AdminService);
//# sourceMappingURL=admin.service.js.map