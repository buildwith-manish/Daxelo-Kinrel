import { Injectable, BadRequestException, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

// In-memory rate limiter for analytics events
interface RateLimitEntry {
  count: number;
  resetAt: number;
}

@Injectable()
export class AnalyticsService {
  private readonly logger = new Logger(AnalyticsService.name);
  private rateLimitMap = new Map<string, RateLimitEntry>();
  private readonly RATE_LIMIT_PER_MINUTE = 100;
  private readonly RATE_LIMIT_WINDOW_MS = 60 * 1000; // 1 minute

  // PII fields to strip from event properties
  private readonly PII_FIELDS = ['email', 'phone', 'name', 'photo', 'avatarUrl', 'phoneNumber', 'e_mail'];

  constructor(private prisma: PrismaService) {}

  /**
   * Track an analytics event
   * Rate limited to 100 events per minute per user
   * PII is sanitized from properties
   */
  async trackEvent(userId: string, event: string, properties?: Record<string, any>) {
    // Rate limit check
    if (!this.checkRateLimit(userId)) {
      throw new BadRequestException('Rate limit exceeded. Maximum 100 events per minute.');
    }

    // Sanitize PII from properties
    let sanitizedProperties: string | null = null;
    if (properties) {
      const sanitized = this.sanitizePii(properties);
      sanitizedProperties = JSON.stringify(sanitized);
    }

    // Store the event
    await this.prisma.analyticsEvent.create({
      data: {
        userId,
        event,
        properties: sanitizedProperties,
      },
    });

    return { success: true };
  }

  /**
   * Get analytics dashboard data (admin only)
   * Returns: dau, mau, newUsersToday, totalFamilies, totalMembers, topEvents, inviteConversion, premiumConversionRate
   */
  async getDashboard() {
    const now = new Date();
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const thirtyDaysAgo = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);

    // DAU — unique users with events today
    const dauResult = await this.prisma.analyticsEvent.findMany({
      where: { createdAt: { gte: todayStart } },
      select: { userId: true },
      distinct: ['userId'],
    });
    const dau = dauResult.length;

    // MAU — unique users with events in last 30 days
    const mauResult = await this.prisma.analyticsEvent.findMany({
      where: { createdAt: { gte: thirtyDaysAgo } },
      select: { userId: true },
      distinct: ['userId'],
    });
    const mau = mauResult.length;

    // New users today
    const newUsersToday = await this.prisma.user.count({
      where: { createdAt: { gte: todayStart } },
    });

    // Total families
    const totalFamilies = await this.prisma.family.count();

    // Total family members (persons, not FamilyMember)
    const totalMembers = await this.prisma.person.count({
      where: { deletedAt: null },
    });

    // Top events (last 30 days)
    const topEventsRaw = await this.prisma.analyticsEvent.groupBy({
      by: ['event'],
      where: { createdAt: { gte: thirtyDaysAgo } },
      _count: { event: true },
      orderBy: { _count: { event: 'desc' } },
      take: 10,
    });
    const topEvents = topEventsRaw.map((e) => ({
      event: e.event,
      count: e._count.event,
    }));

    // Invite conversion: accepted / total invitations
    const totalInvitations = await this.prisma.invitation.count();
    const acceptedInvitations = await this.prisma.invitation.count({
      where: { status: 'accepted' },
    });
    const inviteConversion = totalInvitations > 0
      ? Number(((acceptedInvitations / totalInvitations) * 100).toFixed(2))
      : 0;

    // Premium conversion rate: premium users / total users
    const totalUsers = await this.prisma.user.count();
    const premiumUsers = await this.prisma.user.count({
      where: { isPremium: true },
    });
    const premiumConversionRate = totalUsers > 0
      ? Number(((premiumUsers / totalUsers) * 100).toFixed(2))
      : 0;

    return {
      dau,
      mau,
      newUsersToday,
      totalFamilies,
      totalMembers,
      topEvents,
      inviteConversion,
      premiumConversionRate,
    };
  }

  /**
   * Check rate limit for a user
   * Returns true if under the limit, false if over
   */
  private checkRateLimit(userId: string): boolean {
    const now = Date.now();
    const entry = this.rateLimitMap.get(userId);

    if (!entry || now > entry.resetAt) {
      // Create new window
      this.rateLimitMap.set(userId, {
        count: 1,
        resetAt: now + this.RATE_LIMIT_WINDOW_MS,
      });
      return true;
    }

    if (entry.count >= this.RATE_LIMIT_PER_MINUTE) {
      return false;
    }

    entry.count++;
    return true;
  }

  /**
   * Sanitize PII from properties object
   * Strips email, phone, name, photo fields
   */
  private sanitizePii(obj: Record<string, any>): Record<string, any> {
    const sanitized = { ...obj };

    for (const key of Object.keys(sanitized)) {
      if (this.PII_FIELDS.includes(key)) {
        delete sanitized[key];
      } else if (typeof sanitized[key] === 'object' && sanitized[key] !== null) {
        sanitized[key] = this.sanitizePii(sanitized[key]);
      }
    }

    return sanitized;
  }
}
