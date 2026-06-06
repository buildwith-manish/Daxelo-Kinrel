import {
  Injectable,
  BadRequestException,
  NotFoundException,
  ForbiddenException,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { TicketCategory, TicketSeverity } from '@prisma/client';

// SLA deadlines per tier (in hours)
const SLA_DEADLINES: Record<string, { firstResponse: number; resolution: number }> = {
  basic: { firstResponse: 24, resolution: 72 },
  standard: { firstResponse: 8, resolution: 48 },
  premium: { firstResponse: 4, resolution: 24 },
  vip: { firstResponse: 1, resolution: 8 },
};

// Queue routing by category
const CATEGORY_QUEUE: Record<string, string> = {
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

const SEVERITY_PRIORITY: Record<string, number> = {
  critical: 100,
  high: 75,
  medium: 50,
  low: 25,
};

@Injectable()
export class SupportService {
  constructor(private prisma: PrismaService) {}

  /**
   * Create a support ticket with auto-generated ticket number, queue routing, and SLA.
   */
  async createTicket(
    userId: string,
    data: {
      subject: string;
      description: string;
      category?: string;
      subcategory?: string;
      severity?: string;
      attachments?: string[];
      appVersion?: string;
      platform?: string;
      deviceInfo?: string;
      language?: string;
    },
  ) {
    // Get user's subscription tier
    const subscription = await this.prisma.subscription.findUnique({
      where: { userId },
    });

    const slaTier = subscription?.supportTier || 'basic';
    const category = data.category || 'general';
    const severity = data.severity || 'medium';

    // Generate ticket number: DK-YYYY-NNNNN
    const ticketNumber = await this.generateTicketNumber();

    // Auto-route to queue
    const queue = CATEGORY_QUEUE[category] || 'general';

    // Calculate SLA deadlines
    const now = new Date();
    const sla = SLA_DEADLINES[slaTier] || SLA_DEADLINES.basic;
    const firstResponseDeadline = new Date(
      now.getTime() + sla.firstResponse * 60 * 60 * 1000,
    );
    const resolutionDeadline = new Date(
      now.getTime() + sla.resolution * 60 * 60 * 1000,
    );

    const ticket = await this.prisma.supportTicket.create({
      data: {
        ticketNumber,
        userId,
        category: category as TicketCategory,
        subcategory: data.subcategory || null,
        severity: severity as TicketSeverity,
        priority: SEVERITY_PRIORITY[severity] || 50,
        subject: data.subject,
        description: data.description,
        attachments: data.attachments || [],
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

    // Create SLA tracking record
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

  /**
   * List all tickets (paginated) — admin/agent view.
   */
  async listTickets(
    page: number = 1,
    limit: number = 20,
    filters?: { status?: string; category?: string; queue?: string },
  ) {
    const skip = (page - 1) * limit;
    const where: any = {};

    if (filters?.status) where.status = filters.status;
    if (filters?.category) where.category = filters.category;
    if (filters?.queue) where.queue = filters.queue;

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

  /**
   * Get user's own tickets.
   */
  async listMyTickets(userId: string, page: number = 1, limit: number = 20) {
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

  /**
   * Add a message to a ticket.
   */
  async addMessage(
    ticketId: string,
    userId: string,
    data: {
      content: string;
      attachments?: string[];
      senderType?: string;
      channel?: string;
    },
  ) {
    const ticket = await this.prisma.supportTicket.findUnique({
      where: { id: ticketId },
    });

    if (!ticket) {
      throw new NotFoundException('Ticket not found');
    }

    // Only the ticket owner or an agent can add messages
    if (ticket.userId !== userId) {
      // Check if user is an agent assigned to this ticket
      const agent = await this.prisma.supportAgent.findUnique({
        where: { userId },
      });
      if (!agent || (ticket.assignedAgentId && ticket.assignedAgentId !== agent.id)) {
        throw new ForbiddenException(
          'You are not authorized to add messages to this ticket',
        );
      }
    }

    // Determine sender name and type
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    const senderType = data.senderType || (ticket.userId === userId ? 'user' : 'agent');

    const message = await this.prisma.supportMessage.create({
      data: {
        ticketId,
        senderType,
        senderId: userId,
        senderName: user?.name || user?.email || 'Unknown',
        content: data.content,
        attachments: data.attachments || [],
        channel: data.channel || 'in_app',
      },
    });

    // If first response by agent, record it
    if (
      senderType === 'agent' &&
      !ticket.firstResponseAt &&
      ticket.status === 'open'
    ) {
      await this.prisma.supportTicket.update({
        where: { id: ticketId },
        data: {
          firstResponseAt: new Date(),
          status: 'in_progress',
        },
      });

      // Mark first_response SLA as met
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
      attachments: message.attachments,
      channel: message.channel,
      createdAt: message.createdAt,
    };
  }

  /**
   * Submit CSAT rating for a ticket.
   */
  async submitCSAT(
    ticketId: string,
    userId: string,
    data: { rating: number; comment?: string },
  ) {
    const ticket = await this.prisma.supportTicket.findUnique({
      where: { id: ticketId },
    });

    if (!ticket) {
      throw new NotFoundException('Ticket not found');
    }

    if (ticket.userId !== userId) {
      throw new ForbiddenException(
        'Only the ticket owner can submit a CSAT rating',
      );
    }

    if (ticket.status !== 'resolved' && ticket.status !== 'closed') {
      throw new BadRequestException(
        'CSAT can only be submitted for resolved or closed tickets',
      );
    }

    if (data.rating < 1 || data.rating > 5) {
      throw new BadRequestException('Rating must be between 1 and 5');
    }

    // Check if CSAT already exists
    const existing = await this.prisma.supportCSAT.findUnique({
      where: { ticketId },
    });

    if (existing) {
      throw new BadRequestException('CSAT rating already submitted for this ticket');
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

  /**
   * Generate ticket number: TK-YYYYMMDD-NNNN
   * Wrapped in a transaction with collision detection to prevent race conditions.
   */
  private async generateTicketNumber(): Promise<string> {
    return this.prisma.$transaction(async (tx) => {
      const today = new Date();
      const prefix = `TK-${today.getFullYear()}${String(today.getMonth() + 1).padStart(2, '0')}${String(today.getDate()).padStart(2, '0')}`;
      const startOfDay = new Date(today.getFullYear(), today.getMonth(), today.getDate());
      const endOfDay = new Date(startOfDay.getTime() + 24 * 60 * 60 * 1000);

      const count = await tx.supportTicket.count({
        where: { createdAt: { gte: startOfDay, lt: endOfDay } },
      });

      const ticketNumber = `${prefix}-${String(count + 1).padStart(4, '0')}`;

      // Verify uniqueness - if collision, increment
      const existing = await tx.supportTicket.findFirst({ where: { ticketNumber } });
      if (existing) {
        // Collision - find next available number
        const allToday = await tx.supportTicket.findMany({
          where: { ticketNumber: { startsWith: prefix }, createdAt: { gte: startOfDay, lt: endOfDay } },
          select: { ticketNumber: true },
          orderBy: { ticketNumber: 'desc' },
          take: 1,
        });
        const lastNum = allToday.length > 0 ? parseInt(allToday[0].ticketNumber.split('-').pop() || '0') : 0;
        return `${prefix}-${String(lastNum + 1).padStart(4, '0')}`;
      }

      return ticketNumber;
    });
  }

  private formatTicket(ticket: any) {
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
}
