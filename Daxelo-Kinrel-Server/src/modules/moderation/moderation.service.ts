import {
  Injectable,
  NotFoundException,
  ForbiddenException,
  ConflictException,
  BadRequestException,
  Logger,
} from '@nestjs/common';
import { PrismaService } from '@/common/prisma/prisma.service';
import { ReportDto } from './dto/report.dto';
import { ReviewDto } from './dto/review.dto';
import { AppealDto, AppealReviewDto } from './dto/appeal.dto';
import { CreateRuleDto, ToggleRuleDto } from './dto/rule.dto';

// ── Constants ───────────────────────────────────────────────────────

const MAX_REPORTS_PER_USER_PER_HOUR = 10;
const MIN_APPEAL_LENGTH = 10;
const MAX_APPEAL_LENGTH = 2000;
const APPEAL_WINDOW_HOURS = 48;
const MAX_APPEALS_PER_CASE = 2;

// ── Moderator Check ─────────────────────────────────────────────────

async function isUserModerator(prisma: PrismaService, userId: string): Promise<boolean> {
  const user = await prisma.user.findUnique({ where: { id: userId } });
  return user?.role === 'admin' || user?.role === 'agent';
}

@Injectable()
export class ModerationService {
  private readonly logger = new Logger(ModerationService.name);

  constructor(private readonly prisma: PrismaService) {}

  // ── Submit Report ─────────────────────────────────────────────────

  async submitReport(dto: ReportDto) {
    // Check reporter exists
    const reporter = await this.prisma.user.findUnique({ where: { id: dto.reporterId } });
    if (!reporter) throw new NotFoundException('Reporter not found');

    // Rate limit: max 10 reports per user per hour
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
    const recentReports = await this.prisma.contentReport.count({
      where: { reporterId: dto.reporterId, createdAt: { gte: oneHourAgo } },
    });
    if (recentReports >= MAX_REPORTS_PER_USER_PER_HOUR) {
      throw new ConflictException('Rate limit exceeded. Maximum 10 reports per hour.');
    }

    // Dedup
    const existingReport = await this.prisma.contentReport.findFirst({
      where: {
        reporterId: dto.reporterId,
        targetType: dto.targetType,
        targetId: dto.targetId,
        status: { in: ['pending', 'reviewing'] },
      },
    });
    if (existingReport) {
      throw new ConflictException({
        message: 'You have already reported this content and it is under review.',
        reportId: existingReport.id,
      });
    }

    const report = await this.prisma.contentReport.create({
      data: {
        reporterId: dto.reporterId,
        targetType: dto.targetType,
        targetId: dto.targetId,
        reason: dto.reason,
        description: dto.description || null,
        status: 'pending',
      },
    });

    // Also create a moderation case
    await this.prisma.moderationCase.create({
      data: {
        contentType: dto.targetType,
        contentId: dto.targetId,
        contentPreview: dto.description ? dto.description.substring(0, 500) : null,
        authorId: 'unknown',
        category: dto.reason,
        confidence: 0.5,
        autoAction: 'allow_with_flag',
        flaggedCategories: JSON.stringify([dto.reason]),
        status: 'pending',
        priority: dto.reason === 'sexual_content' || dto.reason === 'violence' ? 'urgent' : 'normal',
        source: 'user_report',
        reporterId: dto.reporterId,
        reportReason: dto.reason,
        reportDetails: dto.description || null,
      },
    });

    return {
      id: report.id,
      status: report.status,
      message: 'Report submitted successfully. Our moderation team will review it.',
    };
  }

  // ── Get Moderation Queue ──────────────────────────────────────────

  async getQueue(options: {
    userId: string;
    status?: string;
    priority?: string;
    category?: string;
    limit?: number;
  }) {
    const isMod = await isUserModerator(this.prisma, options.userId);
    if (!isMod) throw new ForbiddenException('Access denied. Moderator role required.');

    const where: Record<string, unknown> = {};
    if (options.priority) where.priority = options.priority;
    if (options.category) where.category = options.category;

    if (!options.status) {
      where.status = { in: ['pending', 'under_review'] };
    } else {
      where.status = options.status;
    }

    const limit = Math.min(options.limit ?? 50, 100);

    const cases = await this.prisma.moderationCase.findMany({
      where,
      orderBy: [{ priority: 'desc' }, { createdAt: 'asc' }],
      take: limit,
    });

    const statusCounts = await this.prisma.moderationCase.groupBy({
      by: ['status'],
      _count: { id: true },
    });

    const queueStats = {
      pending: statusCounts.find((s) => s.status === 'pending')?._count.id || 0,
      underReview: statusCounts.find((s) => s.status === 'under_review')?._count.id || 0,
      actioned: statusCounts.find((s) => s.status === 'actioned')?._count.id || 0,
      escalated: statusCounts.find((s) => s.status === 'escalated')?._count.id || 0,
      appealed: statusCounts.find((s) => s.status === 'appealed')?._count.id || 0,
    };

    return { cases, stats: queueStats, total: cases.length };
  }

  // ── Review Case ───────────────────────────────────────────────────

  async reviewCase(dto: ReviewDto) {
    const isMod = await isUserModerator(this.prisma, dto.moderatorId);
    if (!isMod) throw new ForbiddenException('Access denied. Moderator role required.');

    const modCase = await this.prisma.moderationCase.findUnique({ where: { id: dto.caseId } });
    if (!modCase) throw new NotFoundException('Case not found');

    const actionMap: Record<string, string> = {
      approve: 'none',
      reject: dto.contentAction || 'removed',
      restrict: 'hidden',
      escalate: modCase.contentAction || 'hidden',
    };

    // Apply the action
    await this.prisma.moderationCase.update({
      where: { id: dto.caseId },
      data: {
        contentAction: actionMap[dto.action],
        reviewerId: dto.moderatorId,
        reviewedAt: new Date(),
        reviewDecision: dto.action === 'approve' ? 'dismiss' : dto.action === 'reject' ? 'uphold' : dto.action,
        reviewNotes: dto.notes || null,
        status: dto.action === 'approve' ? 'dismissed' : dto.action === 'escalate' ? 'escalated' : 'actioned',
        ...(dto.action === 'escalate' ? { priority: 'urgent' } : {}),
      },
    });

    // Log the moderation action
    await this.prisma.moderationAction.create({
      data: {
        moderatorId: dto.moderatorId,
        targetType: modCase.contentType,
        targetId: modCase.contentId,
        action: dto.action === 'approve' ? 'pin' : dto.action === 'reject' ? 'delete' : dto.action === 'restrict' ? 'hide' : 'lock',
        reason: dto.notes || `Moderator action: ${dto.action}`,
      },
    });

    const actionVerbs: Record<string, string> = {
      approve: 'approved',
      reject: 'rejected',
      restrict: 'restricted',
      escalate: 'escalated',
    };

    return {
      caseId: dto.caseId,
      action: dto.action,
      message: `Case ${dto.caseId} has been ${actionVerbs[dto.action]}.`,
    };
  }

  // ── Submit Appeal ─────────────────────────────────────────────────

  async submitAppeal(dto: AppealDto) {
    const modCase = await this.prisma.moderationCase.findUnique({ where: { id: dto.caseId } });
    if (!modCase) throw new NotFoundException('Moderation case not found');

    if (modCase.authorId !== dto.appellantId) {
      throw new ForbiddenException('Only the content author can file an appeal');
    }

    // Check 48-hour window
    const hoursSinceCase = (Date.now() - modCase.createdAt.getTime()) / (1000 * 60 * 60);
    if (hoursSinceCase > APPEAL_WINDOW_HOURS) {
      throw new BadRequestException(`Appeals must be filed within ${APPEAL_WINDOW_HOURS} hours of the action`);
    }

    // Check max appeals per case
    const existingAppeals = await this.prisma.moderationAppeal.count({ where: { caseId: dto.caseId } });
    if (existingAppeals >= MAX_APPEALS_PER_CASE) {
      throw new BadRequestException(`Maximum ${MAX_APPEALS_PER_CASE} appeals allowed per case`);
    }

    const currentTier = existingAppeals + 1;

    const appeal = await this.prisma.moderationAppeal.create({
      data: {
        caseId: dto.caseId,
        appellantId: dto.appellantId,
        appealReason: dto.appealReason,
        appealTier: currentTier,
        status: 'pending',
      },
    });

    // Update case status
    await this.prisma.moderationCase.update({
      where: { id: dto.caseId },
      data: { status: 'appealed' },
    });

    // Log the appeal
    await this.prisma.moderationActionItem.create({
      data: {
        caseId: dto.caseId,
        actionType: 'appealed',
        actorId: dto.appellantId,
        details: JSON.stringify({ appealId: appeal.id, tier: currentTier, timestamp: new Date().toISOString() }),
      },
    });

    // Audit log
    await this.prisma.moderationAuditLog.create({
      data: {
        action: 'appeal',
        contentType: modCase.contentType,
        contentId: modCase.contentId,
        actorType: 'system',
        actorId: dto.appellantId,
        result: 'appeal_filed',
        reason: dto.appealReason.substring(0, 500),
        metadata: JSON.stringify({ appealId: appeal.id, tier: currentTier }),
      },
    });

    return {
      id: appeal.id,
      caseId: dto.caseId,
      tier: currentTier,
      status: appeal.status,
      message: currentTier === 1
        ? 'Your appeal has been filed. A moderator will review it within 48 hours.'
        : 'Your tier 2 appeal has been filed. A different moderator will review it within 24 hours.',
    };
  }

  // ── Review Appeal ─────────────────────────────────────────────────

  async reviewAppeal(appealId: string, dto: AppealReviewDto) {
    const appeal = await this.prisma.moderationAppeal.findUnique({ where: { id: appealId } });
    if (!appeal) throw new NotFoundException('Appeal not found');

    if (appeal.status !== 'pending' && appeal.status !== 'under_review') {
      throw new BadRequestException(`Appeal is already ${appeal.status}`);
    }

    // For tier 2, ensure different moderator
    if (appeal.appealTier === 2 && appeal.reviewerId === dto.reviewerId) {
      throw new ForbiddenException('Tier 2 appeal must be reviewed by a different moderator than tier 1');
    }

    const reviewer = await this.prisma.user.findUnique({ where: { id: dto.reviewerId } });
    if (!reviewer || (reviewer.role !== 'admin' && reviewer.role !== 'agent')) {
      throw new ForbiddenException('Only moderators can review appeals');
    }

    // Update the appeal
    await this.prisma.moderationAppeal.update({
      where: { id: appealId },
      data: {
        status: dto.decision === 'upheld' ? 'upheld' : dto.decision,
        reviewerId: dto.reviewerId,
        reviewedAt: new Date(),
        reviewDecision: dto.decision,
        reviewNotes: dto.notes || null,
      },
    });

    // Update the moderation case
    const caseId = appeal.caseId;
    if (dto.decision === 'reinstated' || dto.decision === 'dismissed') {
      await this.prisma.moderationCase.update({
        where: { id: caseId },
        data: { status: 'dismissed', contentAction: 'none', reviewDecision: dto.decision, reviewNotes: dto.notes || null },
      });
    } else if (dto.decision === 'reduced') {
      const modCase = await this.prisma.moderationCase.findUnique({ where: { id: caseId } });
      await this.prisma.moderationCase.update({
        where: { id: caseId },
        data: {
          contentAction: modCase?.contentAction === 'removed' ? 'hidden' : 'none',
          reviewDecision: 'reduced',
          reviewNotes: dto.notes || null,
        },
      });
    } else {
      await this.prisma.moderationCase.update({
        where: { id: caseId },
        data: { status: 'actioned', reviewDecision: 'uphold', reviewNotes: dto.notes || null },
      });
    }

    // Log action
    await this.prisma.moderationActionItem.create({
      data: {
        caseId,
        actionType: 'appeal_reviewed',
        actorId: dto.reviewerId,
        details: JSON.stringify({ appealId, decision: dto.decision, tier: appeal.appealTier, timestamp: new Date().toISOString() }),
      },
    });

    // Audit log
    await this.prisma.moderationAuditLog.create({
      data: {
        action: 'appeal',
        contentType: 'mixed',
        contentId: caseId,
        actorType: 'human_moderator',
        actorId: dto.reviewerId,
        result: dto.decision,
        reason: dto.notes || `Appeal ${dto.decision}`,
        metadata: JSON.stringify({ appealId, tier: appeal.appealTier }),
      },
    });

    const messages: Record<string, string> = {
      upheld: 'The original action stands.',
      reinstated: 'Content has been restored.',
      reduced: 'The action has been reduced.',
      dismissed: 'The case has been dismissed.',
    };

    return {
      appealId,
      decision: dto.decision,
      message: `Appeal has been ${dto.decision}. ${messages[dto.decision]}`,
    };
  }

  // ── Moderation Stats ──────────────────────────────────────────────

  async getStats(userId: string) {
    const isMod = await isUserModerator(this.prisma, userId);
    if (!isMod) throw new ForbiddenException('Access denied. Moderator role required.');

    const now = new Date();
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const last7Days = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
    const last30Days = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);

    const [pendingCount, resolvedToday, csamCount, csamPending, pendingReports, totalAppeals, pendingAppeals, resolvedAppeals, categoryBreakdown, priorityBreakdown, sourceBreakdown, userStatusBreakdown] = await Promise.all([
      this.prisma.moderationCase.count({ where: { status: { in: ['pending', 'under_review'] } } }),
      this.prisma.moderationCase.count({ where: { status: { in: ['actioned', 'dismissed'] }, reviewedAt: { gte: todayStart } } }),
      this.prisma.moderationCase.count({ where: { category: 'csam', createdAt: { gte: last30Days } } }),
      this.prisma.moderationCase.count({ where: { category: 'csam', status: { in: ['pending', 'escalated'] } } }),
      this.prisma.contentReport.count({ where: { status: 'pending' } }),
      this.prisma.moderationAppeal.count({ where: { createdAt: { gte: last30Days } } }),
      this.prisma.moderationAppeal.count({ where: { status: { in: ['pending', 'under_review'] } } }),
      this.prisma.moderationAppeal.count({ where: { status: { in: ['upheld', 'reinstated', 'reduced', 'dismissed'] }, createdAt: { gte: last30Days } } }),
      this.prisma.moderationCase.groupBy({ by: ['category'], _count: { id: true }, where: { createdAt: { gte: last30Days } } }),
      this.prisma.moderationCase.groupBy({ by: ['priority'], _count: { id: true }, where: { status: { in: ['pending', 'under_review'] } } }),
      this.prisma.moderationCase.groupBy({ by: ['source'], _count: { id: true }, where: { createdAt: { gte: last30Days } } }),
      this.prisma.userModerationStatus.groupBy({ by: ['status'], _count: { id: true } }),
    ]);

    // Avg resolution time
    const resolvedCases = await this.prisma.moderationCase.findMany({
      where: { status: { in: ['actioned', 'dismissed'] }, reviewedAt: { not: null }, createdAt: { gte: last7Days } },
      select: { createdAt: true, reviewedAt: true },
    });
    const resolutionTimes = resolvedCases
      .filter((c) => c.reviewedAt)
      .map((c) => (c.reviewedAt!.getTime() - c.createdAt.getTime()) / (1000 * 60 * 60));
    const avgResolutionHours = resolutionTimes.length > 0
      ? Math.round((resolutionTimes.reduce((a, b) => a + b, 0) / resolutionTimes.length) * 10) / 10
      : 0;

    const appealResolutionRate = totalAppeals > 0 ? Math.round((resolvedAppeals / totalAppeals) * 100) : 0;

    // Daily trend
    const dailyTrend: Array<{ date: string; created: number; resolved: number }> = [];
    for (let i = 6; i >= 0; i--) {
      const dayStart = new Date(now.getTime() - i * 24 * 60 * 60 * 1000);
      dayStart.setHours(0, 0, 0, 0);
      const dayEnd = new Date(dayStart.getTime() + 24 * 60 * 60 * 1000);

      const [created, resolved] = await Promise.all([
        this.prisma.moderationCase.count({ where: { createdAt: { gte: dayStart, lt: dayEnd } } }),
        this.prisma.moderationCase.count({ where: { reviewedAt: { gte: dayStart, lt: dayEnd }, status: { in: ['actioned', 'dismissed'] } } }),
      ]);

      dailyTrend.push({ date: dayStart.toISOString().split('T')[0], created, resolved });
    }

    return {
      overview: { pendingCount, resolvedToday, avgResolutionHours, csamCount, csamPending, pendingReports },
      appeals: { total: totalAppeals, pending: pendingAppeals, resolved: resolvedAppeals, resolutionRate: appealResolutionRate },
      breakdowns: {
        byCategory: categoryBreakdown.map((b) => ({ category: b.category, count: b._count.id })),
        byPriority: priorityBreakdown.map((b) => ({ priority: b.priority, count: b._count.id })),
        bySource: sourceBreakdown.map((b) => ({ source: b.source, count: b._count.id })),
        userStatuses: userStatusBreakdown.map((b) => ({ status: b.status, count: b._count.id })),
      },
      dailyTrend,
      period: 'last_30_days',
      generatedAt: now.toISOString(),
    };
  }

  // ── List Rules ────────────────────────────────────────────────────

  async listRules(options: { userId: string; category?: string; activeOnly?: boolean }) {
    const isMod = await isUserModerator(this.prisma, options.userId);
    if (!isMod) throw new ForbiddenException('Access denied. Moderator role required.');

    const where: Record<string, unknown> = {};
    if (options.category) where.category = options.category;
    if (options.activeOnly) where.isActive = true;

    const rules = await this.prisma.moderationRule.findMany({
      where,
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
      stats: { total: rules.length, active: activeCount, inactive: inactiveCount, categories: Object.keys(byCategory).length },
      byCategory,
    };
  }

  // ── Create Rule ───────────────────────────────────────────────────

  async createRule(dto: CreateRuleDto) {
    if (!dto.createdBy) throw new BadRequestException('createdBy (userId) is required');
    const isMod = await isUserModerator(this.prisma, dto.createdBy);
    if (!isMod) throw new ForbiddenException('Access denied. Moderator role required.');

    const existing = await this.prisma.moderationRule.findFirst({ where: { name: dto.name } });
    if (existing) throw new ConflictException(`Rule with name "${dto.name}" already exists`);

    const rule = await this.prisma.moderationRule.create({
      data: {
        name: dto.name,
        description: dto.description || null,
        contentType: dto.contentType || null,
        category: dto.category,
        condition: dto.condition,
        action: dto.action,
        priority: dto.priority || 'normal',
        isActive: true,
        createdBy: dto.createdBy,
      },
    });

    await this.prisma.moderationAuditLog.create({
      data: {
        action: 'classify',
        contentType: 'rule',
        contentId: rule.id,
        actorType: 'human_moderator',
        actorId: dto.createdBy,
        result: 'allow',
        reason: `Created rule: ${dto.name}`,
        metadata: JSON.stringify({ ruleId: rule.id, category: dto.category, action: dto.action }),
      },
    });

    return { rule, message: 'Rule created successfully' };
  }

  // ── Toggle Rule ───────────────────────────────────────────────────

  async toggleRule(dto: ToggleRuleDto) {
    const isMod = await isUserModerator(this.prisma, dto.userId);
    if (!isMod) throw new ForbiddenException('Access denied. Moderator role required.');

    const rule = await this.prisma.moderationRule.findUnique({ where: { id: dto.ruleId } });
    if (!rule) throw new NotFoundException('Rule not found');

    const updated = await this.prisma.moderationRule.update({
      where: { id: dto.ruleId },
      data: { isActive: dto.isActive },
    });

    await this.prisma.moderationAuditLog.create({
      data: {
        action: 'classify',
        contentType: 'rule',
        contentId: dto.ruleId,
        actorType: 'human_moderator',
        actorId: dto.userId,
        result: dto.isActive ? 'allow' : 'reject',
        reason: `Rule "${rule.name}" ${dto.isActive ? 'activated' : 'deactivated'}`,
        metadata: JSON.stringify({ ruleId: dto.ruleId, isActive: dto.isActive, ruleName: rule.name }),
      },
    });

    return { rule: updated, message: `Rule "${rule.name}" has been ${dto.isActive ? 'activated' : 'deactivated'}` };
  }
}
