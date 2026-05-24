import {
  Injectable,
  NotFoundException,
  ConflictException,
  BadRequestException,
  Logger,
} from '@nestjs/common';
import { PrismaService } from '@/common/prisma/prisma.service';
import { CreateTicketDto } from './dto/create-ticket.dto';
import { CreateMessageDto } from './dto/create-message.dto';
import { CsatDto } from './dto/csat.dto';

// ── SLA tier response times (hours) ────────────────────────────────────

const TIER_MAX_RESPONSE_HOURS: Record<string, number> = {
  basic: 24,
  standard: 8,
  premium: 4,
  vip: 1,
};

function tierMaxResponseTime(tier: string): number {
  return TIER_MAX_RESPONSE_HOURS[tier] ?? 24;
}

async function getUserSupportTier(
  prisma: PrismaService,
  userId: string,
): Promise<string> {
  const subscription = await prisma.subscription.findUnique({
    where: { userId },
    select: { supportTier: true },
  });
  return subscription?.supportTier ?? 'basic';
}

async function generateTicketNumber(
  prisma: PrismaService,
): Promise<string> {
  const year = new Date().getFullYear();
  const prefix = `DK-${year}-`;

  const lastTicket = await prisma.supportTicket.findFirst({
    where: { ticketNumber: { startsWith: prefix } },
    orderBy: { ticketNumber: 'desc' },
    select: { ticketNumber: true },
  });

  let nextNum = 1;
  if (lastTicket) {
    const parts = lastTicket.ticketNumber.split('-');
    const lastNum = parseInt(parts[parts.length - 1], 10);
    if (!isNaN(lastNum)) nextNum = lastNum + 1;
  }

  return `${prefix}${String(nextNum).padStart(5, '0')}`;
}

async function routeTicket(
  prisma: PrismaService,
  ticketId: string,
): Promise<{
  assignedAgentId: string | null;
  queue: string;
  priority: number;
  estimatedResponseHours: number;
}> {
  // Simple routing logic — find available agent with lowest load
  const agent = await prisma.supportAgent.findFirst({
    where: { status: 'online', currentLoad: { lt: 10 } },
    orderBy: { currentLoad: 'asc' },
  });

  const ticket = await prisma.supportTicket.findUnique({
    where: { id: ticketId },
  });

  const queue = ticket?.category ?? 'general';
  const priority = ticket?.severity === 'critical' ? 100 : ticket?.severity === 'high' ? 75 : ticket?.severity === 'medium' ? 50 : 25;
  const estimatedResponseHours = agent ? 2 : 8;

  if (agent) {
    await prisma.supportAgent.update({
      where: { id: agent.id },
      data: { currentLoad: { increment: 1 } },
    });
  }

  return {
    assignedAgentId: agent?.id ?? null,
    queue,
    priority,
    estimatedResponseHours,
  };
}

// ═══════════════════════════════════════════════════════════════════════
// SupportService
// ═══════════════════════════════════════════════════════════════════════

@Injectable()
export class SupportService {
  private readonly logger = new Logger(SupportService.name);

  constructor(private readonly prisma: PrismaService) {}

  // ── Create Ticket ─────────────────────────────────────────────────

  async createTicket(userId: string, dto: CreateTicketDto) {
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user) throw new NotFoundException('User not found');

    const tier = await getUserSupportTier(this.prisma, userId);
    const maxResponseHours = tierMaxResponseTime(tier);
    const ticketNumber = await generateTicketNumber(this.prisma);

    const now = new Date();
    const firstResponseDeadline = new Date(now.getTime() + maxResponseHours * 60 * 60 * 1000);
    const resolutionDeadline = new Date(now.getTime() + maxResponseHours * 4 * 60 * 60 * 1000);

    const ticket = await this.prisma.supportTicket.create({
      data: {
        ticketNumber,
        userId,
        category: dto.category,
        subcategory: dto.subcategory ?? null,
        severity: dto.severity,
        subject: dto.subject,
        description: dto.description,
        attachments: JSON.stringify(dto.attachments ?? []),
        appVersion: dto.appVersion ?? null,
        platform: dto.platform ?? null,
        deviceInfo: dto.deviceInfo ? JSON.stringify({ info: dto.deviceInfo }) : null,
        slaTier: tier,
        firstResponseDeadline,
        resolutionDeadline,
        language: user.preferredLanguage ?? 'en',
      },
    });

    const routing = await routeTicket(this.prisma, ticket.id);

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

  // ── List All Tickets ──────────────────────────────────────────────

  async listTickets(options: { status?: string; page?: number; limit?: number }) {
    const page = Math.max(1, options.page ?? 1);
    const limit = Math.min(100, Math.max(1, options.limit ?? 20));

    const where: Record<string, unknown> = {};
    if (options.status) where.status = options.status;

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

  // ── My Tickets ────────────────────────────────────────────────────

  async myTickets(userId: string, options: { status?: string; page?: number; limit?: number }) {
    const page = Math.max(1, options.page ?? 1);
    const limit = Math.min(100, Math.max(1, options.limit ?? 20));

    const where: Record<string, unknown> = { userId };
    if (options.status) where.status = options.status;

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

  // ── Add Message ───────────────────────────────────────────────────

  async addMessage(userId: string, ticketId: string, dto: CreateMessageDto) {
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

  // ── Get Messages ──────────────────────────────────────────────────

  async getMessages(userId: string, ticketId: string) {
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

  // ── Submit CSAT ───────────────────────────────────────────────────

  async submitCsat(userId: string, ticketId: string, dto: CsatDto) {
    const ticket = await this.prisma.supportTicket.findUnique({ where: { id: ticketId } });
    if (!ticket || ticket.userId !== userId) {
      throw new NotFoundException('Not found');
    }

    if (ticket.status !== 'resolved' && ticket.status !== 'closed') {
      throw new BadRequestException('CSAT can only be submitted for resolved tickets');
    }

    const existing = await this.prisma.supportCSAT.findUnique({ where: { ticketId } });
    if (existing) {
      throw new ConflictException('CSAT already submitted for this ticket');
    }

    const csat = await this.prisma.supportCSAT.create({
      data: {
        ticketId,
        rating: dto.rating,
        comment: dto.comment ?? null,
      },
    });

    return { csat };
  }
}
