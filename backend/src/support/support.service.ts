import { Injectable, BadRequestException, NotFoundException, ConflictException, UnauthorizedException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { CreateTicketDto } from './dto/create-ticket.dto';
import { CreateMessageDto } from './dto/create-message.dto';
import { CreateCsatDto } from './dto/create-csat.dto';

@Injectable()
export class SupportService {
  constructor(private prisma: PrismaService) {}

  // ── Support Helpers ──────────────────────────────────────────────

  /**
   * Generate ticket number in DK-YYYY-NNNNN format
   */
  async generateTicketNumber(): Promise<string> {
    const year = new Date().getFullYear();
    const prefix = `DK-${year}-`;

    // Find the last ticket number for this year
    const lastTicket = await this.prisma.supportTicket.findFirst({
      where: {
        ticketNumber: { startsWith: prefix },
      },
      orderBy: { ticketNumber: 'desc' },
      select: { ticketNumber: true },
    });

    let nextNumber = 1;
    if (lastTicket) {
      const parts = lastTicket.ticketNumber.split('-');
      const lastNum = parseInt(parts[parts.length - 1], 10);
      nextNumber = lastNum + 1;
    }

    return `${prefix}${nextNumber.toString().padStart(5, '0')}`;
  }

  /**
   * Calculate SLA deadlines based on tier
   */
  calculateSlaDeadlines(tier: string): { firstResponseHours: number; resolutionHours: number } {
    const tierMap: Record<string, { firstResponseHours: number; resolutionHours: number }> = {
      vip: { firstResponseHours: 1, resolutionHours: 4 },
      premium: { firstResponseHours: 2, resolutionHours: 8 },
      standard: { firstResponseHours: 4, resolutionHours: 24 },
      basic: { firstResponseHours: 8, resolutionHours: 48 },
    };

    return tierMap[tier] ?? tierMap.basic;
  }

  /**
   * Look up user's support tier from subscription
   */
  async getUserSupportTier(userId: string): Promise<string> {
    const subscription = await this.prisma.subscription.findUnique({
      where: { userId },
    });

    return subscription?.supportTier ?? 'basic';
  }

  /**
   * Simplified ticket routing — assigns to available agent or defaults queue
   */
  async routeTicket(ticketId: string): Promise<{
    assignedAgentId: string | null;
    queue: string;
    priority: number;
    estimatedResponseHours: number;
  }> {
    // Find an available agent with lowest current load
    const agent = await this.prisma.supportAgent.findFirst({
      where: {
        status: { in: ['online', 'busy'] },
        currentLoad: { lt: 10 },
      },
      orderBy: [
        { currentLoad: 'asc' },
        { avgResponseTime: 'asc' },
      ],
    });

    if (agent) {
      // Increment agent load
      await this.prisma.supportAgent.update({
        where: { id: agent.id },
        data: { currentLoad: { increment: 1 } },
      });
    }

    return {
      assignedAgentId: agent?.id ?? null,
      queue: 'general',
      priority: 1,
      estimatedResponseHours: 8,
    };
  }

  // ── Ticket CRUD ──────────────────────────────────────────────────

  /**
   * POST /api/support/tickets — Create ticket
   */
  async createTicket(userId: string, dto: CreateTicketDto) {
    // Ensure user exists
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) {
      throw new NotFoundException('User not found');
    }

    const tier = await this.getUserSupportTier(userId);
    const { firstResponseHours, resolutionHours } = this.calculateSlaDeadlines(tier);

    // Generate human-readable ticket number
    const ticketNumber = await this.generateTicketNumber();

    // Calculate SLA deadlines
    const now = new Date();
    const firstResponseDeadline = new Date(now.getTime() + firstResponseHours * 60 * 60 * 1000);
    const resolutionDeadline = new Date(now.getTime() + resolutionHours * 60 * 60 * 1000);

    const ticket = await this.prisma.supportTicket.create({
      data: {
        ticketNumber,
        userId,
        category: dto.category,
        subcategory: dto.subcategory,
        severity: dto.severity,
        subject: dto.subject,
        description: dto.description,
        attachments: JSON.stringify(dto.attachments ?? []),
        appVersion: dto.appVersion,
        platform: dto.platform,
        deviceInfo: dto.deviceInfo ? JSON.stringify({ info: dto.deviceInfo }) : null,
        slaTier: tier,
        firstResponseDeadline,
        resolutionDeadline,
        language: user.preferredLanguage ?? 'en',
      },
    });

    // Route ticket to agent/queue
    const routing = await this.routeTicket(ticket.id);

    // Update ticket with routing info
    await this.prisma.supportTicket.update({
      where: { id: ticket.id },
      data: {
        assignedAgentId: routing.assignedAgentId,
        queue: routing.queue,
        priority: routing.priority,
      },
    });

    return {
      ticket: {
        id: ticket.id,
        ticketNumber: ticket.ticketNumber,
        status: ticket.status,
        category: ticket.category,
        severity: ticket.severity,
        slaTier: ticket.slaTier,
        estimatedResponseHours: routing.estimatedResponseHours,
        queue: routing.queue,
        priority: routing.priority,
        firstResponseDeadline: ticket.firstResponseDeadline,
        resolutionDeadline: ticket.resolutionDeadline,
        createdAt: ticket.createdAt,
      },
    };
  }

  /**
   * GET /api/support/tickets?status=&page=&limit=
   * List tickets (paginated)
   */
  async listTickets(params: { status?: string; page?: number; limit?: number }) {
    const page = params.page ?? 1;
    const limit = params.limit ?? 20;

    const where: Record<string, unknown> = {};
    if (params.status) where.status = params.status;

    const [tickets, total] = await Promise.all([
      this.prisma.supportTicket.findMany({
        where,
        include: {
          user: { select: { id: true, name: true, email: true } },
          assignedAgent: { select: { id: true, name: true } },
          csat: { select: { rating: true } },
          messages: { take: 1, orderBy: { createdAt: 'desc' } },
        },
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * limit,
        take: limit,
      }),
      this.prisma.supportTicket.count({ where }),
    ]);

    return { tickets, total, page, limit };
  }

  /**
   * GET /api/support/tickets/my — User's own tickets
   */
  async getMyTickets(userId: string, params: { status?: string; page?: number; limit?: number }) {
    const page = params.page ?? 1;
    const limit = params.limit ?? 20;

    const where: Record<string, unknown> = { userId };
    if (params.status) where.status = params.status;

    const [tickets, total] = await Promise.all([
      this.prisma.supportTicket.findMany({
        where,
        include: {
          messages: { take: 1, orderBy: { createdAt: 'desc' } },
          assignedAgent: { select: { name: true } },
          csat: { select: { rating: true } },
        },
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * limit,
        take: limit,
      }),
      this.prisma.supportTicket.count({ where }),
    ]);

    return { tickets, total, page, limit };
  }

  // ── Messages ─────────────────────────────────────────────────────

  /**
   * POST /api/support/tickets/:ticketId/messages — Add message
   */
  async createMessage(userId: string, ticketId: string, dto: CreateMessageDto) {
    const ticket = await this.prisma.supportTicket.findUnique({ where: { id: ticketId } });

    if (!ticket || ticket.userId !== userId) {
      throw new NotFoundException('Not found');
    }

    // Reopen if ticket was resolved
    if (ticket.status === 'resolved' || ticket.status === 'closed') {
      await this.prisma.supportTicket.update({
        where: { id: ticketId },
        data: { status: 'open', resolvedAt: null },
      });
    }

    const user = await this.prisma.user.findUnique({ where: { id: userId } });

    const message = await this.prisma.supportMessage.create({
      data: {
        ticketId,
        senderType: 'user',
        senderId: userId,
        senderName: user?.name ?? 'User',
        content: dto.content,
        attachments: JSON.stringify(dto.attachments ?? []),
        channel: dto.channel ?? 'in_app',
      },
    });

    return { message };
  }

  /**
   * GET /api/support/tickets/:ticketId/messages — List messages for ticket
   */
  async listMessages(userId: string, ticketId: string) {
    const ticket = await this.prisma.supportTicket.findUnique({ where: { id: ticketId } });

    if (!ticket || ticket.userId !== userId) {
      throw new NotFoundException('Not found');
    }

    const messages = await this.prisma.supportMessage.findMany({
      where: { ticketId, isInternal: false },
      orderBy: { createdAt: 'asc' },
    });

    return { messages };
  }

  // ── CSAT ─────────────────────────────────────────────────────────

  /**
   * POST /api/support/tickets/:ticketId/csat — Submit CSAT
   */
  async createCsat(userId: string, ticketId: string, dto: CreateCsatDto) {
    const ticket = await this.prisma.supportTicket.findUnique({ where: { id: ticketId } });

    if (!ticket || ticket.userId !== userId) {
      throw new NotFoundException('Not found');
    }

    if (ticket.status !== 'resolved' && ticket.status !== 'closed') {
      throw new BadRequestException('CSAT can only be submitted for resolved tickets');
    }

    // Check if CSAT already exists
    const existing = await this.prisma.supportCSAT.findUnique({ where: { ticketId } });
    if (existing) {
      throw new ConflictException('CSAT already submitted for this ticket');
    }

    const csat = await this.prisma.supportCSAT.create({
      data: {
        ticketId,
        rating: dto.rating,
        comment: dto.comment,
      },
    });

    return { csat };
  }
}
