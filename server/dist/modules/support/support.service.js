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
exports.SupportService = void 0;
const common_1 = require("@nestjs/common");
const prisma_service_1 = require("../../prisma/prisma.service");
const SLA_DEADLINES = {
    basic: { firstResponse: 24, resolution: 72 },
    standard: { firstResponse: 8, resolution: 48 },
    premium: { firstResponse: 4, resolution: 24 },
    vip: { firstResponse: 1, resolution: 8 },
};
const CATEGORY_QUEUE = {
    billing: 'billing',
    account: 'account',
    data_loss: 'critical',
    bug: 'technical',
    feature_request: 'product',
    general: 'general',
    matrimonial: 'verification',
    verification: 'verification',
    privacy: 'legal',
};
const SEVERITY_PRIORITY = {
    critical: 100,
    high: 75,
    medium: 50,
    low: 25,
};
let SupportService = class SupportService {
    constructor(prisma) {
        this.prisma = prisma;
    }
    async createTicket(userId, data) {
        const subscription = await this.prisma.subscription.findUnique({
            where: { userId },
        });
        const slaTier = subscription?.supportTier || 'basic';
        const category = data.category || 'general';
        const severity = data.severity || 'medium';
        const ticketNumber = await this.generateTicketNumber();
        const queue = CATEGORY_QUEUE[category] || 'general';
        const now = new Date();
        const sla = SLA_DEADLINES[slaTier] || SLA_DEADLINES.basic;
        const firstResponseDeadline = new Date(now.getTime() + sla.firstResponse * 60 * 60 * 1000);
        const resolutionDeadline = new Date(now.getTime() + sla.resolution * 60 * 60 * 1000);
        const ticket = await this.prisma.supportTicket.create({
            data: {
                ticketNumber,
                userId,
                category,
                subcategory: data.subcategory || null,
                severity,
                priority: SEVERITY_PRIORITY[severity] || 50,
                subject: data.subject,
                description: data.description,
                attachments: JSON.stringify(data.attachments || []),
                appVersion: data.appVersion || null,
                platform: data.platform || null,
                deviceInfo: data.deviceInfo || null,
                queue,
                slaTier,
                firstResponseDeadline,
                resolutionDeadline,
                language: data.language || 'en',
            },
            include: {
                user: { select: { id: true, name: true, email: true } },
            },
        });
        await this.prisma.sLATracking.create({
            data: {
                ticketId: ticket.id,
                type: 'first_response',
                tier: slaTier,
                deadline: firstResponseDeadline,
            },
        });
        await this.prisma.sLATracking.create({
            data: {
                ticketId: ticket.id,
                type: 'resolution',
                tier: slaTier,
                deadline: resolutionDeadline,
            },
        });
        return this.formatTicket(ticket);
    }
    async listTickets(page = 1, limit = 20, filters) {
        const skip = (page - 1) * limit;
        const where = {};
        if (filters?.status)
            where.status = filters.status;
        if (filters?.category)
            where.category = filters.category;
        if (filters?.queue)
            where.queue = filters.queue;
        const [tickets, total] = await Promise.all([
            this.prisma.supportTicket.findMany({
                where,
                skip,
                take: limit,
                include: {
                    user: { select: { id: true, name: true, email: true } },
                    assignedAgent: {
                        include: { user: { select: { id: true, name: true } } },
                    },
                },
                orderBy: { priority: 'desc' },
            }),
            this.prisma.supportTicket.count({ where }),
        ]);
        return {
            data: tickets.map((t) => this.formatTicket(t)),
            pagination: {
                page,
                limit,
                total,
                totalPages: Math.ceil(total / limit),
            },
        };
    }
    async listMyTickets(userId, page = 1, limit = 20) {
        const skip = (page - 1) * limit;
        const [tickets, total] = await Promise.all([
            this.prisma.supportTicket.findMany({
                where: { userId },
                skip,
                take: limit,
                include: {
                    messages: {
                        orderBy: { createdAt: 'desc' },
                        take: 1,
                    },
                },
                orderBy: { createdAt: 'desc' },
            }),
            this.prisma.supportTicket.count({ where: { userId } }),
        ]);
        return {
            data: tickets.map((t) => this.formatTicket(t)),
            pagination: {
                page,
                limit,
                total,
                totalPages: Math.ceil(total / limit),
            },
        };
    }
    async addMessage(ticketId, userId, data) {
        const ticket = await this.prisma.supportTicket.findUnique({
            where: { id: ticketId },
        });
        if (!ticket) {
            throw new common_1.NotFoundException('Ticket not found');
        }
        if (ticket.userId !== userId) {
            const agent = await this.prisma.supportAgent.findUnique({
                where: { userId },
            });
            if (!agent || (ticket.assignedAgentId && ticket.assignedAgentId !== agent.id)) {
                throw new common_1.ForbiddenException('You are not authorized to add messages to this ticket');
            }
        }
        const user = await this.prisma.user.findUnique({ where: { id: userId } });
        const senderType = data.senderType || (ticket.userId === userId ? 'user' : 'agent');
        const message = await this.prisma.supportMessage.create({
            data: {
                ticketId,
                senderType,
                senderId: userId,
                senderName: user?.name || user?.email || 'Unknown',
                content: data.content,
                attachments: JSON.stringify(data.attachments || []),
                channel: data.channel || 'in_app',
            },
        });
        if (senderType === 'agent' &&
            !ticket.firstResponseAt &&
            ticket.status === 'open') {
            await this.prisma.supportTicket.update({
                where: { id: ticketId },
                data: {
                    firstResponseAt: new Date(),
                    status: 'in_progress',
                },
            });
            await this.prisma.sLATracking.updateMany({
                where: { ticketId, type: 'first_response', metAt: null },
                data: { metAt: new Date() },
            });
        }
        return {
            id: message.id,
            ticketId: message.ticketId,
            senderType: message.senderType,
            senderId: message.senderId,
            senderName: message.senderName,
            content: message.content,
            attachments: JSON.parse(message.attachments),
            channel: message.channel,
            createdAt: message.createdAt,
        };
    }
    async submitCSAT(ticketId, userId, data) {
        const ticket = await this.prisma.supportTicket.findUnique({
            where: { id: ticketId },
        });
        if (!ticket) {
            throw new common_1.NotFoundException('Ticket not found');
        }
        if (ticket.userId !== userId) {
            throw new common_1.ForbiddenException('Only the ticket owner can submit a CSAT rating');
        }
        if (ticket.status !== 'resolved' && ticket.status !== 'closed') {
            throw new common_1.BadRequestException('CSAT can only be submitted for resolved or closed tickets');
        }
        if (data.rating < 1 || data.rating > 5) {
            throw new common_1.BadRequestException('Rating must be between 1 and 5');
        }
        const existing = await this.prisma.supportCSAT.findUnique({
            where: { ticketId },
        });
        if (existing) {
            throw new common_1.BadRequestException('CSAT rating already submitted for this ticket');
        }
        const csat = await this.prisma.supportCSAT.create({
            data: {
                ticketId,
                rating: data.rating,
                comment: data.comment || null,
            },
        });
        return {
            id: csat.id,
            ticketId: csat.ticketId,
            rating: csat.rating,
            comment: csat.comment,
            createdAt: csat.createdAt,
        };
    }
    async generateTicketNumber() {
        const year = new Date().getFullYear();
        const yearStart = new Date(year, 0, 1);
        const yearEnd = new Date(year + 1, 0, 1);
        const count = await this.prisma.supportTicket.count({
            where: {
                createdAt: {
                    gte: yearStart,
                    lt: yearEnd,
                },
            },
        });
        const sequence = (count + 1).toString().padStart(5, '0');
        return `DK-${year}-${sequence}`;
    }
    formatTicket(ticket) {
        return {
            id: ticket.id,
            ticketNumber: ticket.ticketNumber,
            userId: ticket.userId,
            user: ticket.user || undefined,
            category: ticket.category,
            subcategory: ticket.subcategory,
            severity: ticket.severity,
            priority: ticket.priority,
            subject: ticket.subject,
            description: ticket.description,
            status: ticket.status,
            queue: ticket.queue,
            slaTier: ticket.slaTier,
            slaBreached: ticket.slaBreached,
            firstResponseAt: ticket.firstResponseAt,
            firstResponseDeadline: ticket.firstResponseDeadline,
            resolutionDeadline: ticket.resolutionDeadline,
            assignedAgent: ticket.assignedAgent
                ? {
                    id: ticket.assignedAgent.id,
                    name: ticket.assignedAgent.user?.name,
                }
                : null,
            language: ticket.language,
            createdAt: ticket.createdAt,
            updatedAt: ticket.updatedAt,
            resolvedAt: ticket.resolvedAt,
            closedAt: ticket.closedAt,
        };
    }
};
exports.SupportService = SupportService;
exports.SupportService = SupportService = __decorate([
    (0, common_1.Injectable)(),
    __metadata("design:paramtypes", [prisma_service_1.PrismaService])
], SupportService);
//# sourceMappingURL=support.service.js.map