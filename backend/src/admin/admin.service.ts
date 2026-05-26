import { Injectable, NotFoundException, ConflictException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { ListUsersDto } from './dto/list-users.dto';
import { CreateRuleDto } from './dto/create-rule.dto';
import { UpdateRuleDto } from './dto/update-rule.dto';
import { CreateTemplateDto } from './dto/create-template.dto';
import { UpdateTemplateDto } from './dto/update-template.dto';

@Injectable()
export class AdminService {
  constructor(private prisma: PrismaService) {}

  // ── Dashboard stats ─────────────────────────────────────────────────

  async getDashboardStats() {
    const [totalUsers, totalFamilies, totalPersons, totalTickets] = await Promise.all([
      this.prisma.user.count(),
      this.prisma.family.count(),
      this.prisma.person.count({ where: { deletedAt: null } }),
      this.prisma.supportTicket.count(),
    ]);

    const [activeSubscriptions, pendingInvitations, openTickets, totalRelationships] = await Promise.all([
      this.prisma.subscription.count({ where: { status: 'active' } }),
      this.prisma.invitation.count({ where: { status: 'pending' } }),
      this.prisma.supportTicket.count({ where: { status: { in: ['open', 'in_progress'] } } }),
      this.prisma.relationship.count(),
    ]);

    const usersByRole = await this.prisma.user.groupBy({ by: ['role'], _count: { id: true } });
    const ticketsByStatus = await this.prisma.supportTicket.groupBy({ by: ['status'], _count: { id: true } });

    return {
      stats: {
        totalUsers,
        totalFamilies,
        totalPersons,
        totalTickets,
        activeSubscriptions,
        pendingInvitations,
        openTickets,
        totalRelationships,
      },
      breakdown: {
        usersByRole: usersByRole.map((r) => ({ role: r.role, count: r._count.id })),
        ticketsByStatus: ticketsByStatus.map((t) => ({ status: t.status, count: t._count.id })),
      },
    };
  }

  // ── List users ──────────────────────────────────────────────────────

  async listUsers(dto: ListUsersDto) {
    const { page = 1, limit = 20, search, role } = dto;

    const where: Record<string, unknown> = {};
    if (search) {
      where.OR = [
        { name: { contains: search } },
        { email: { contains: search } },
        { phone: { contains: search } },
      ];
    }
    if (role) where.role = role;

    const [users, total] = await Promise.all([
      this.prisma.user.findMany({
        where,
        select: {
          id: true,
          email: true,
          name: true,
          phone: true,
          role: true,
          preferredLanguage: true,
          createdAt: true,
          updatedAt: true,
          subscription: { select: { plan: true, status: true } },
          families: { select: { familyId: true, role: true } },
        },
        orderBy: { createdAt: 'desc' },
        skip: (page - 1) * limit,
        take: limit,
      }),
      this.prisma.user.count({ where }),
    ]);

    return {
      users,
      pagination: {
        page,
        limit,
        total,
        hasMore: page * limit < total,
        totalPages: Math.ceil(total / limit),
      },
    };
  }

  // ── Moderation rules ────────────────────────────────────────────────

  async listRules() {
    const rules = await this.prisma.moderationRule.findMany({
      orderBy: [{ priority: 'desc' }, { name: 'asc' }],
    });

    const activeCount = rules.filter((r) => r.isActive).length;
    const inactiveCount = rules.filter((r) => !r.isActive).length;

    const byCategory: Record<string, typeof rules> = {};
    for (const rule of rules) {
      if (!byCategory[rule.category]) byCategory[rule.category] = [];
      byCategory[rule.category].push(rule);
    }

    return {
      rules,
      stats: {
        total: rules.length,
        active: activeCount,
        inactive: inactiveCount,
        categories: Object.keys(byCategory).length,
      },
      byCategory,
    };
  }

  async createRule(dto: CreateRuleDto, userId: string) {
    const existing = await this.prisma.moderationRule.findFirst({ where: { name: dto.name } });
    if (existing) {
      throw new ConflictException(`Rule with name "${dto.name}" already exists`);
    }

    const rule = await this.prisma.moderationRule.create({
      data: {
        name: dto.name,
        description: dto.description || null,
        contentType: dto.contentType || null,
        category: dto.category,
        condition: dto.condition,
        action: dto.action,
        priority: dto.priority || 'normal',
        isActive: dto.isActive ?? true,
        createdBy: userId,
      },
    });

    // Audit log
    await this.prisma.moderationAuditLog.create({
      data: {
        action: 'classify',
        contentType: 'rule',
        contentId: rule.id,
        actorType: 'human_moderator',
        actorId: userId,
        result: 'allow',
        reason: `Created rule: ${dto.name}`,
        metadata: JSON.stringify({ ruleId: rule.id, category: dto.category, action: dto.action }),
      },
    });

    return { rule, message: 'Rule created successfully' };
  }

  async updateRule(id: string, dto: UpdateRuleDto, userId: string) {
    const rule = await this.prisma.moderationRule.findUnique({ where: { id } });
    if (!rule) throw new NotFoundException('Rule not found');

    const updateData: Record<string, unknown> = {};
    if (dto.name !== undefined) updateData.name = dto.name;
    if (dto.description !== undefined) updateData.description = dto.description;
    if (dto.contentType !== undefined) updateData.contentType = dto.contentType;
    if (dto.category !== undefined) updateData.category = dto.category;
    if (dto.condition !== undefined) updateData.condition = dto.condition;
    if (dto.action !== undefined) updateData.action = dto.action;
    if (dto.priority !== undefined) updateData.priority = dto.priority;
    if (dto.isActive !== undefined) updateData.isActive = dto.isActive;

    const updated = await this.prisma.moderationRule.update({
      where: { id },
      data: updateData,
    });

    // Audit log
    await this.prisma.moderationAuditLog.create({
      data: {
        action: 'classify',
        contentType: 'rule',
        contentId: id,
        actorType: 'human_moderator',
        actorId: userId,
        result: dto.isActive !== false ? 'allow' : 'reject',
        reason: `Updated rule "${rule.name}"`,
        metadata: JSON.stringify({ ruleId: id, updatedFields: Object.keys(updateData) }),
      },
    });

    return { rule: updated, message: `Rule "${rule.name}" has been updated` };
  }

  // ── Moderation stats ────────────────────────────────────────────────

  async getModerationStats() {
    const now = new Date();
    const last30Days = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);

    const pendingCount = await this.prisma.moderationCase.count({
      where: { status: { in: ['pending', 'under_review'] } },
    });

    const resolvedToday = await this.prisma.moderationCase.count({
      where: {
        status: { in: ['actioned', 'dismissed'] },
        reviewedAt: { gte: new Date(now.getFullYear(), now.getMonth(), now.getDate()) },
      },
    });

    // Average resolution time (last 7 days)
    const resolvedCases = await this.prisma.moderationCase.findMany({
      where: {
        status: { in: ['actioned', 'dismissed'] },
        reviewedAt: { not: null },
        createdAt: { gte: new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000) },
      },
      select: { createdAt: true, reviewedAt: true },
    });

    const resolutionTimes = resolvedCases
      .filter((c) => c.reviewedAt)
      .map((c) => (c.reviewedAt!.getTime() - c.createdAt.getTime()) / (1000 * 60 * 60));

    const avgResolutionHours = resolutionTimes.length > 0
      ? Math.round((resolutionTimes.reduce((a, b) => a + b, 0) / resolutionTimes.length) * 10) / 10
      : 0;

    // Appeal stats
    const totalAppeals = await this.prisma.moderationAppeal.count({ where: { createdAt: { gte: last30Days } } });
    const pendingAppeals = await this.prisma.moderationAppeal.count({ where: { status: { in: ['pending', 'under_review'] } } });
    const resolvedAppeals = await this.prisma.moderationAppeal.count({
      where: { status: { in: ['upheld', 'reinstated', 'reduced', 'dismissed'] }, createdAt: { gte: last30Days } },
    });

    const categoryBreakdown = await this.prisma.moderationCase.groupBy({
      by: ['category'],
      _count: { id: true },
      where: { createdAt: { gte: last30Days } },
    });

    const priorityBreakdown = await this.prisma.moderationCase.groupBy({
      by: ['priority'],
      _count: { id: true },
      where: { status: { in: ['pending', 'under_review'] } },
    });

    const sourceBreakdown = await this.prisma.moderationCase.groupBy({
      by: ['source'],
      _count: { id: true },
      where: { createdAt: { gte: last30Days } },
    });

    const pendingReports = await this.prisma.contentReport.count({ where: { status: 'pending' } });

    return {
      overview: { pendingCount, resolvedToday, avgResolutionHours, pendingReports },
      appeals: {
        total: totalAppeals,
        pending: pendingAppeals,
        resolved: resolvedAppeals,
        resolutionRate: totalAppeals > 0 ? Math.round((resolvedAppeals / totalAppeals) * 100) : 0,
      },
      breakdowns: {
        byCategory: categoryBreakdown.map((b) => ({ category: b.category, count: b._count.id })),
        byPriority: priorityBreakdown.map((b) => ({ priority: b.priority, count: b._count.id })),
        bySource: sourceBreakdown.map((b) => ({ source: b.source, count: b._count.id })),
      },
      period: 'last_30_days',
      generatedAt: now.toISOString(),
    };
  }

  // ── SLA report ──────────────────────────────────────────────────────

  async getSlaReport(month?: string) {
    const reportMonth = month || new Date().toISOString().slice(0, 7);

    const startDate = new Date(`${reportMonth}-01`);
    const endDate = new Date(startDate);
    endDate.setMonth(endDate.getMonth() + 1);

    const [totalTickets, breachedTickets, resolvedTickets] = await Promise.all([
      this.prisma.supportTicket.count({ where: { createdAt: { gte: startDate, lt: endDate } } }),
      this.prisma.supportTicket.count({ where: { slaBreached: true, createdAt: { gte: startDate, lt: endDate } } }),
      this.prisma.supportTicket.count({ where: { status: { in: ['resolved', 'closed'] }, createdAt: { gte: startDate, lt: endDate } } }),
    ]);

    const byTier = await this.prisma.supportTicket.groupBy({
      by: ['slaTier'],
      _count: { id: true },
      where: { createdAt: { gte: startDate, lt: endDate } },
    });

    const breachedByTier = await this.prisma.supportTicket.groupBy({
      by: ['slaTier'],
      _count: { id: true },
      where: { slaBreached: true, createdAt: { gte: startDate, lt: endDate } },
    });

    const slaComplianceRate = totalTickets > 0
      ? Math.round(((totalTickets - breachedTickets) / totalTickets) * 100)
      : 100;

    return {
      month: reportMonth,
      totalTickets,
      breachedTickets,
      resolvedTickets,
      slaComplianceRate,
      byTier: byTier.map((t) => ({
        tier: t.slaTier,
        total: t._count.id,
        breached: breachedByTier.find((b) => b.slaTier === t.slaTier)?._count.id || 0,
      })),
    };
  }

  // ── WhatsApp templates ──────────────────────────────────────────────

  async listTemplates(status?: string) {
    const where: Record<string, unknown> = {};
    if (status) where.status = status;

    const templates = await this.prisma.whatsAppTemplate.findMany({
      where,
      orderBy: { createdAt: 'desc' },
    });

    const parsedTemplates = templates.map((t) => ({
      ...t,
      languages: JSON.parse(t.languages) as string[],
      components: JSON.parse(t.components) as Record<string, unknown>,
    }));

    return { templates: parsedTemplates };
  }

  async createTemplate(dto: CreateTemplateDto) {
    const existing = await this.prisma.whatsAppTemplate.findUnique({ where: { name: dto.name } });
    if (existing) {
      throw new ConflictException(`Template with name "${dto.name}" already exists`);
    }

    const template = await this.prisma.whatsAppTemplate.create({
      data: {
        name: dto.name,
        category: dto.category,
        status: 'pending',
        languages: JSON.stringify(dto.languages),
        components: dto.components,
      },
    });

    return {
      template: {
        ...template,
        languages: JSON.parse(template.languages) as string[],
        components: JSON.parse(template.components) as Record<string, unknown>,
      },
    };
  }

  async updateTemplate(id: string, dto: UpdateTemplateDto) {
    const template = await this.prisma.whatsAppTemplate.findUnique({ where: { id } });
    if (!template) throw new NotFoundException('Template not found');

    const updateData: Record<string, unknown> = {};
    if (dto.name !== undefined) updateData.name = dto.name;
    if (dto.category !== undefined) updateData.category = dto.category;
    if (dto.languages !== undefined) updateData.languages = JSON.stringify(dto.languages);
    if (dto.components !== undefined) updateData.components = dto.components;
    if (dto.status !== undefined) updateData.status = dto.status;

    const updated = await this.prisma.whatsAppTemplate.update({
      where: { id },
      data: updateData,
    });

    return {
      template: {
        ...updated,
        languages: JSON.parse(updated.languages) as string[],
        components: JSON.parse(updated.components) as Record<string, unknown>,
      },
    };
  }

  // ── KB analytics ────────────────────────────────────────────────────

  async getKbAnalytics(days = 30) {
    const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000);

    const topArticles = await this.prisma.kBArticle.findMany({
      where: { status: 'published' },
      orderBy: { views: 'desc' },
      take: 20,
      select: {
        id: true,
        slug: true,
        title: true,
        views: true,
        helpfulYes: true,
        helpfulNo: true,
        category: true,
      },
    });

    // Failed searches
    const failedSearchesRaw = await this.prisma.kBSearchLog.findMany({
      where: { ledToTicket: true, createdAt: { gte: since } },
      orderBy: { createdAt: 'desc' },
      take: 50,
      select: { query: true, language: true, createdAt: true },
    });

    const failedSearchCounts: Record<string, number> = {};
    for (const s of failedSearchesRaw) {
      const key = s.query.toLowerCase();
      failedSearchCounts[key] = (failedSearchCounts[key] || 0) + 1;
    }
    const failedSearches = Object.entries(failedSearchCounts)
      .map(([query, count]) => ({ query, count }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 20);

    // Content gaps (no-result searches)
    const noResultSearches = await this.prisma.kBSearchLog.findMany({
      where: { resultsCount: 0, createdAt: { gte: since } },
      orderBy: { createdAt: 'desc' },
      take: 50,
      select: { query: true, language: true },
    });

    const noResultCounts: Record<string, { query: string; count: number; languages: Set<string> }> = {};
    for (const s of noResultSearches) {
      const key = s.query.toLowerCase();
      if (!noResultCounts[key]) noResultCounts[key] = { query: key, count: 0, languages: new Set() };
      noResultCounts[key].count++;
      noResultCounts[key].languages.add(s.language);
    }

    const contentGaps = Object.values(noResultCounts)
      .map(({ query, count, languages }) => ({ query, count, languages: Array.from(languages) }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 20);

    // Parse titles for display
    const articlesWithTitles = topArticles.map((a) => {
      let title = '';
      try { const t = JSON.parse(a.title as string) as Record<string, string>; title = t['en'] || ''; } catch { title = String(a.title); }
      return { ...a, title };
    });

    const totalSearches = await this.prisma.kBSearchLog.count({ where: { createdAt: { gte: since } } });
    const totalArticles = await this.prisma.kBArticle.count({ where: { status: 'published' } });

    return {
      days,
      topArticles: articlesWithTitles,
      failedSearches,
      contentGaps,
      totalSearches,
      totalArticles,
    };
  }
}
