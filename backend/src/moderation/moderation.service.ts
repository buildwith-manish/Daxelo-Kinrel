import { Injectable, NotFoundException, BadRequestException, ForbiddenException, ConflictException, HttpException, HttpStatus } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { ClassifyContentDto } from './dto/classify-content.dto';
import { ReportContentDto } from './dto/report-content.dto';
import { QueueQueryDto } from './dto/queue-query.dto';
import { ModeratorActionDto } from './dto/moderator-action.dto';
import { AppealDto } from './dto/appeal.dto';
import { AppealReviewDto } from './dto/appeal-review.dto';

// ── Stub Classification Logic ─────────────────────────────────────────

const HIGH_RISK = ['violence', 'kill', 'threat', 'weapon', 'bomb', 'nude', 'sexual', 'porn'];
const MEDIUM_RISK = ['hate', 'abuse', 'harass', 'stupid', 'idiot', 'caste', 'untouchable'];
const PII_PATTERNS = ['aadhaar', 'pan card', 'social security', 'credit card', 'bank account', 'password', 'pin number'];

function performStubClassification(contentType: string, content: string) {
  const lower = content.toLowerCase();

  for (const p of HIGH_RISK) {
    if (lower.includes(p)) return { category: 'violence', confidence: 0.85, autoAction: 'quarantine' };
  }
  for (const p of MEDIUM_RISK) {
    if (lower.includes(p)) return { category: 'harassment', confidence: 0.7, autoAction: 'allow_with_flag' };
  }
  for (const p of PII_PATTERNS) {
    if (lower.includes(p)) return { category: 'pii_exposure', confidence: 0.75, autoAction: 'allow_with_flag' };
  }
  return { category: 'safe', confidence: 0.95, autoAction: 'allow' };
}

// ── Constants ─────────────────────────────────────────────────────────

const MAX_REPORTS_PER_HOUR = 5;
const APPEAL_WINDOW_HOURS = 48;
const MAX_APPEALS_PER_CASE = 2;
const MIN_APPEAL_LENGTH = 10;

@Injectable()
export class ModerationService {
  constructor(private prisma: PrismaService) {}

  // ── Classify content ────────────────────────────────────────────────

  async classifyContent(dto: ClassifyContentDto, userId: string) {
    // Use stub classification (in production, integrate AI moderation)
    const result = performStubClassification(dto.contentType, dto.contentPreview || '');

    // Create a moderation case
    const modCase = await this.prisma.moderationCase.create({
      data: {
        contentType: dto.contentType,
        contentId: dto.contentId,
        contentPreview: dto.contentPreview?.substring(0, 500) || null,
        authorId: dto.authorId || userId,
        familyId: dto.familyId || null,
        category: result.category,
        confidence: result.confidence,
        autoAction: result.autoAction,
        flaggedCategories: JSON.stringify([result.category]),
        status: result.autoAction === 'allow' ? 'actioned' : 'pending',
        priority: result.autoAction === 'quarantine' ? 'urgent' : 'normal',
        source: 'auto',
      },
    });

    // Log the auto-action
    await this.prisma.moderationActionItem.create({
      data: {
        caseId: modCase.id,
        actionType: `auto_${result.autoAction}`,
        actorId: null,
        details: JSON.stringify({ category: result.category, confidence: result.confidence }),
      },
    });

    return {
      category: result.category,
      confidence: result.confidence,
      autoAction: result.autoAction,
      flaggedCategories: [result.category],
      caseId: modCase.id,
    };
  }

  // ── Report content ──────────────────────────────────────────────────

  async reportContent(dto: ReportContentDto) {
    const { reporterId, targetType, targetId, reason, description } = dto;

    // Check reporter exists
    const reporter = await this.prisma.user.findUnique({ where: { id: reporterId } });
    if (!reporter) throw new NotFoundException('Reporter not found');

    // Rate limit: max reports per hour
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
    const recentReports = await this.prisma.contentReport.count({
      where: { reporterId, createdAt: { gte: oneHourAgo } },
    });
    if (recentReports >= MAX_REPORTS_PER_HOUR) {
      throw new HttpException('Rate limit exceeded. Maximum 5 reports per hour.', HttpStatus.TOO_MANY_REQUESTS);
    }

    // Dedup check
    const existing = await this.prisma.contentReport.findFirst({
      where: { reporterId, targetType, targetId, status: { in: ['pending', 'reviewing'] } },
    });
    if (existing) {
      throw new ConflictException('You have already reported this content and it is under review.');
    }

    // Create the report
    const report = await this.prisma.contentReport.create({
      data: {
        reporterId,
        targetType,
        targetId,
        reason,
        description: description || null,
        status: 'pending',
      },
    });

    // Create a moderation case
    const isUrgent = reason === 'sexual_content' || reason === 'violence';
    await this.prisma.moderationCase.create({
      data: {
        contentType: targetType,
        contentId: targetId,
        contentPreview: description ? description.substring(0, 500) : null,
        authorId: 'unknown',
        category: reason,
        confidence: 0.5,
        autoAction: 'allow_with_flag',
        flaggedCategories: JSON.stringify([reason]),
        status: 'pending',
        priority: isUrgent ? 'urgent' : 'normal',
        source: 'user_report',
        reporterId,
        reportReason: reason,
        reportDetails: description || null,
      },
    });

    return {
      id: report.id,
      status: report.status,
      message: 'Report submitted successfully. Our moderation team will review it.',
    };
  }

  // ── Get moderation queue ────────────────────────────────────────────

  async getQueue(dto: QueueQueryDto, userId: string) {
    // Verify moderator role
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user || (user.role !== 'admin' && user.role !== 'agent')) {
      throw new ForbiddenException('Access denied. Moderator role required.');
    }

    const { status, priority, page = 1, limit = 50 } = dto;

    const where: Record<string, unknown> = {};
    if (status) where.status = status;
    if (priority) where.priority = priority;

    if (!status) {
      where.status = { in: ['pending', 'under_review'] };
    }

    const cases = await this.prisma.moderationCase.findMany({
      where,
      orderBy: [{ priority: 'desc' }, { createdAt: 'asc' }],
      take: Math.min(limit, 100),
      skip: (page - 1) * limit,
    });

    // Status counts
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

  // ── Moderator action ────────────────────────────────────────────────

  async moderatorAction(dto: ModeratorActionDto, userId: string) {
    // Verify moderator role
    const user = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!user || (user.role !== 'admin' && user.role !== 'agent')) {
      throw new ForbiddenException('Access denied. Moderator role required.');
    }

    const modCase = await this.prisma.moderationCase.findUnique({ where: { id: dto.caseId } });
    if (!modCase) throw new NotFoundException('Case not found');

    const actionMap: Record<string, string> = {
      approve: 'none',
      reject: 'removed',
      restrict: 'hidden',
      escalate: modCase.contentAction || 'hidden',
    };

    const updateData: Record<string, unknown> = {
      reviewerId: userId,
      reviewedAt: new Date(),
      contentAction: actionMap[dto.action],
    };

    if (dto.action === 'escalate') {
      updateData.status = 'escalated';
      updateData.priority = 'urgent';
    } else if (dto.action === 'approve') {
      updateData.status = 'dismissed';
      updateData.reviewDecision = 'dismiss';
    } else {
      updateData.status = 'actioned';
      updateData.reviewDecision = 'uphold';
    }

    if (dto.notes) updateData.reviewNotes = dto.notes;

    await this.prisma.moderationCase.update({
      where: { id: dto.caseId },
      data: updateData,
    });

    // Log the action
    await this.prisma.moderationActionItem.create({
      data: {
        caseId: dto.caseId,
        actionType: 'reviewed',
        actorId: userId,
        details: JSON.stringify({ action: dto.action, notes: dto.notes }),
      },
    });

    // Audit log
    await this.prisma.moderationAuditLog.create({
      data: {
        action: 'review',
        contentType: modCase.contentType,
        contentId: modCase.contentId,
        actorType: 'human_moderator',
        actorId: userId,
        result: dto.action,
        reason: dto.notes || `Moderator action: ${dto.action}`,
        metadata: JSON.stringify({ caseId: dto.caseId }),
      },
    });

    return {
      caseId: dto.caseId,
      action: dto.action,
      message: `Case ${dto.caseId} has been ${dto.action === 'approve' ? 'approved' : dto.action === 'reject' ? 'rejected' : dto.action === 'restrict' ? 'restricted' : 'escalated'}.`,
    };
  }

  // ── File appeal ─────────────────────────────────────────────────────

  async fileAppeal(dto: AppealDto) {
    const { caseId, appellantId, appealReason } = dto;

    if (appealReason.length < MIN_APPEAL_LENGTH) {
      throw new BadRequestException(`Appeal reason must be at least ${MIN_APPEAL_LENGTH} characters`);
    }

    const modCase = await this.prisma.moderationCase.findUnique({ where: { id: caseId } });
    if (!modCase) throw new NotFoundException('Moderation case not found');

    if (modCase.authorId !== appellantId) {
      throw new ForbiddenException('Only the content author can file an appeal');
    }

    // Check 48-hour window
    const hoursSinceCase = (Date.now() - modCase.createdAt.getTime()) / (1000 * 60 * 60);
    if (hoursSinceCase > APPEAL_WINDOW_HOURS) {
      throw new BadRequestException(`Appeals must be filed within ${APPEAL_WINDOW_HOURS} hours of the action`);
    }

    // Check max appeals
    const existingAppeals = await this.prisma.moderationAppeal.count({ where: { caseId } });
    if (existingAppeals >= MAX_APPEALS_PER_CASE) {
      throw new BadRequestException(`Maximum ${MAX_APPEALS_PER_CASE} appeals allowed per case`);
    }

    const currentTier = existingAppeals + 1;
    if (currentTier > 2) {
      throw new BadRequestException('Maximum appeal tiers exhausted');
    }

    const appeal = await this.prisma.moderationAppeal.create({
      data: {
        caseId,
        appellantId,
        appealReason,
        appealTier: currentTier,
        status: 'pending',
      },
    });

    await this.prisma.moderationCase.update({
      where: { id: caseId },
      data: { status: 'appealed' },
    });

    await this.prisma.moderationActionItem.create({
      data: {
        caseId,
        actionType: 'appealed',
        actorId: appellantId,
        details: JSON.stringify({ appealId: appeal.id, tier: currentTier }),
      },
    });

    // Audit log
    await this.prisma.moderationAuditLog.create({
      data: {
        action: 'appeal',
        contentType: modCase.contentType,
        contentId: modCase.contentId,
        actorType: 'system',
        actorId: appellantId,
        result: 'appeal_filed',
        reason: appealReason.substring(0, 500),
        metadata: JSON.stringify({ appealId: appeal.id, tier: currentTier }),
      },
    });

    return {
      id: appeal.id,
      caseId,
      tier: currentTier,
      status: appeal.status,
      message: currentTier === 1
        ? 'Your appeal has been filed. A moderator will review it within 48 hours.'
        : 'Your tier 2 appeal has been filed. A different moderator will review it within 24 hours.',
    };
  }

  // ── Review appeal ───────────────────────────────────────────────────

  async reviewAppeal(appealId: string, dto: AppealReviewDto, userId: string) {
    const { reviewDecision, reviewNotes } = dto;

    const appeal = await this.prisma.moderationAppeal.findUnique({ where: { id: appealId } });
    if (!appeal) throw new NotFoundException('Appeal not found');

    if (appeal.status !== 'pending' && appeal.status !== 'under_review') {
      throw new BadRequestException(`Appeal is already ${appeal.status}`);
    }

    // Verify moderator role
    const reviewer = await this.prisma.user.findUnique({ where: { id: userId } });
    if (!reviewer || (reviewer.role !== 'admin' && reviewer.role !== 'agent')) {
      throw new ForbiddenException('Only moderators can review appeals');
    }

    // Tier 2 must be different reviewer
    if (appeal.appealTier === 2 && appeal.reviewerId === userId) {
      throw new ForbiddenException('Tier 2 appeal must be reviewed by a different moderator than tier 1');
    }

    // Update the appeal
    await this.prisma.moderationAppeal.update({
      where: { id: appealId },
      data: {
        status: reviewDecision === 'upheld' ? 'upheld' : reviewDecision,
        reviewerId: userId,
        reviewedAt: new Date(),
        reviewDecision,
        reviewNotes: reviewNotes || null,
      },
    });

    // Update the case based on decision
    const caseId = appeal.caseId;
    if (reviewDecision === 'reinstated' || reviewDecision === 'dismissed') {
      await this.prisma.moderationCase.update({
        where: { id: caseId },
        data: {
          status: 'dismissed',
          contentAction: 'none',
          reviewDecision,
          reviewNotes: reviewNotes || null,
        },
      });
    } else if (reviewDecision === 'reduced') {
      const modCase = await this.prisma.moderationCase.findUnique({ where: { id: caseId } });
      await this.prisma.moderationCase.update({
        where: { id: caseId },
        data: {
          contentAction: modCase?.contentAction === 'removed' ? 'hidden' : 'none',
          reviewDecision: 'reduced',
          reviewNotes: reviewNotes || null,
        },
      });
    } else {
      await this.prisma.moderationCase.update({
        where: { id: caseId },
        data: {
          status: 'actioned',
          reviewDecision: 'uphold',
          reviewNotes: reviewNotes || null,
        },
      });
    }

    // Log
    await this.prisma.moderationActionItem.create({
      data: {
        caseId,
        actionType: 'appeal_reviewed',
        actorId: userId,
        details: JSON.stringify({ appealId, decision: reviewDecision, tier: appeal.appealTier }),
      },
    });

    // Audit log
    await this.prisma.moderationAuditLog.create({
      data: {
        action: 'appeal',
        contentType: 'mixed',
        contentId: caseId,
        actorType: 'human_moderator',
        actorId: userId,
        result: reviewDecision,
        reason: reviewNotes || `Appeal ${reviewDecision}`,
        metadata: JSON.stringify({ appealId, tier: appeal.appealTier }),
      },
    });

    return {
      appealId,
      decision: reviewDecision,
      message: `Appeal has been ${reviewDecision}. ${reviewDecision === 'upheld' ? 'The original action stands.' : reviewDecision === 'reinstated' ? 'Content has been restored.' : reviewDecision === 'reduced' ? 'The action has been reduced.' : 'The case has been dismissed.'}`,
    };
  }
}
