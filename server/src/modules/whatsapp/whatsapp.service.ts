import {
  Injectable,
  BadRequestException,
  NotFoundException,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class WhatsAppService {
  constructor(private prisma: PrismaService) {}

  /**
   * Get consent status for a user.
   */
  async getConsent(userId: string) {
    const consent = await this.prisma.whatsAppConsent.findUnique({
      where: { userId },
    });

    if (!consent) {
      return {
        userId,
        optedIn: false,
        phone: null,
        marketingConsent: false,
        messageCategories: [],
      };
    }

    return {
      userId: consent.userId,
      optedIn: consent.optedIn,
      phone: consent.phone,
      optInMethod: consent.optInMethod,
      optInAt: consent.optInAt,
      optOutAt: consent.optOutAt,
      optOutMethod: consent.optOutMethod,
      optOutReason: consent.optOutReason,
      consentVersion: consent.consentVersion,
      messageCategories: JSON.parse(consent.messageCategories || '[]'),
      marketingConsent: consent.marketingConsent,
      marketingOptInAt: consent.marketingOptInAt,
      createdAt: consent.createdAt,
      updatedAt: consent.updatedAt,
    };
  }

  /**
   * Opt-in to WhatsApp notifications (DPDP Act compliant).
   */
  async optIn(
    userId: string,
    data: {
      phone: string;
      optInMethod?: string;
      messageCategories?: string[];
    },
  ) {
    if (!data.phone || data.phone.trim().length === 0) {
      throw new BadRequestException('Phone number is required');
    }

    const existing = await this.prisma.whatsAppConsent.findUnique({
      where: { userId },
    });

    if (existing) {
      // Update existing consent
      const updated = await this.prisma.whatsAppConsent.update({
        where: { userId },
        data: {
          phone: data.phone.trim(),
          optedIn: true,
          optInMethod: data.optInMethod || 'app_settings',
          optInAt: new Date(),
          optOutAt: null,
          optOutMethod: null,
          optOutReason: null,
          messageCategories: JSON.stringify(
            data.messageCategories || [
              'birthday_reminder',
              'family_invite',
              'new_match',
            ],
          ),
          consentVersion: 'v1',
        },
      });

      // Log the opt-in event
      await this.logConsentEvent(userId, 'opt_in.completed', data.phone);

      return this.formatConsent(updated);
    }

    // Create new consent record
    const consent = await this.prisma.whatsAppConsent.create({
      data: {
        userId,
        phone: data.phone.trim(),
        optedIn: true,
        optInMethod: data.optInMethod || 'app_settings',
        optInAt: new Date(),
        messageCategories: JSON.stringify(
          data.messageCategories || [
            'birthday_reminder',
            'family_invite',
            'new_match',
          ],
        ),
        consentVersion: 'v1',
      },
    });

    // Log the opt-in event
    await this.logConsentEvent(userId, 'opt_in.completed', data.phone);

    return this.formatConsent(consent);
  }

  /**
   * Opt-out of WhatsApp notifications.
   */
  async optOut(
    userId: string,
    data: {
      optOutMethod?: string;
      optOutReason?: string;
    },
  ) {
    const existing = await this.prisma.whatsAppConsent.findUnique({
      where: { userId },
    });

    if (!existing) {
      throw new NotFoundException('No WhatsApp consent record found for this user');
    }

    if (!existing.optedIn) {
      throw new BadRequestException('User is already opted out');
    }

    const updated = await this.prisma.whatsAppConsent.update({
      where: { userId },
      data: {
        optedIn: false,
        optOutAt: new Date(),
        optOutMethod: data.optOutMethod || 'app_settings',
        optOutReason: data.optOutReason || null,
        marketingConsent: false,
      },
    });

    // Log the opt-out event
    await this.logConsentEvent(userId, 'opt_out.requested', existing.phone, {
      method: data.optOutMethod || 'app_settings',
      reason: data.optOutReason,
    });

    return this.formatConsent(updated);
  }

  /**
   * Update marketing consent specifically.
   */
  async updateMarketingConsent(
    userId: string,
    data: {
      marketingConsent: boolean;
    },
  ) {
    const existing = await this.prisma.whatsAppConsent.findUnique({
      where: { userId },
    });

    if (!existing) {
      throw new NotFoundException('No WhatsApp consent record found for this user');
    }

    if (!existing.optedIn) {
      throw new BadRequestException(
        'Cannot update marketing consent when user is opted out',
      );
    }

    const updated = await this.prisma.whatsAppConsent.update({
      where: { userId },
      data: {
        marketingConsent: data.marketingConsent,
        marketingOptInAt: data.marketingConsent ? new Date() : null,
      },
    });

    // Log the marketing consent change
    await this.logConsentEvent(
      userId,
      data.marketingConsent
        ? 'opt_in.completed'
        : 'opt_out.requested',
      existing.phone,
      { type: 'marketing_consent', value: data.marketingConsent },
    );

    return this.formatConsent(updated);
  }

  /**
   * Get WhatsApp analytics.
   */
  async getAnalytics(filters?: {
    event?: string;
    startDate?: string;
    endDate?: string;
    userId?: string;
  }) {
    const where: any = {};

    if (filters?.event) {
      where.event = filters.event;
    }

    if (filters?.userId) {
      where.userId = filters.userId;
    }

    if (filters?.startDate || filters?.endDate) {
      where.createdAt = {};
      if (filters.startDate) {
        where.createdAt.gte = new Date(filters.startDate);
      }
      if (filters.endDate) {
        where.createdAt.lte = new Date(filters.endDate);
      }
    }

    const [events, total] = await Promise.all([
      this.prisma.whatsAppAnalytics.findMany({
        where,
        orderBy: { createdAt: 'desc' },
        take: 100,
      }),
      this.prisma.whatsAppAnalytics.count({ where }),
    ]);

    // Aggregate by event type
    const eventCounts: Record<string, number> = {};
    for (const event of events) {
      eventCounts[event.event] = (eventCounts[event.event] || 0) + 1;
    }

    return {
      events: events.map((e) => ({
        id: e.id,
        event: e.event,
        userId: e.userId,
        familyId: e.familyId,
        messageId: e.messageId,
        templateId: e.templateId,
        metadata: JSON.parse(e.metadata || '{}'),
        createdAt: e.createdAt,
      })),
      summary: {
        total,
        eventCounts,
      },
    };
  }

  /**
   * Track a WhatsApp analytics event.
   */
  async trackEvent(
    data: {
      event: string;
      userId?: string;
      familyId?: string;
      messageId?: string;
      templateId?: string;
      metadata?: Record<string, any>;
    },
  ) {
    const analytics = await this.prisma.whatsAppAnalytics.create({
      data: {
        event: data.event,
        userId: data.userId || null,
        familyId: data.familyId || null,
        messageId: data.messageId || null,
        templateId: data.templateId || null,
        metadata: JSON.stringify(data.metadata || {}),
      },
    });

    return {
      id: analytics.id,
      event: analytics.event,
      createdAt: analytics.createdAt,
    };
  }

  /**
   * Internal: Log consent events for DPDP Act compliance.
   */
  private async logConsentEvent(
    userId: string,
    event: string,
    phone: string,
    metadata?: Record<string, any>,
  ) {
    await this.prisma.whatsAppAnalytics.create({
      data: {
        event: `whatsapp.${event}`,
        userId,
        metadata: JSON.stringify({
          phone,
          timestamp: new Date().toISOString(),
          ...metadata,
        }),
      },
    });
  }

  private formatConsent(consent: any) {
    return {
      userId: consent.userId,
      phone: consent.phone,
      optedIn: consent.optedIn,
      optInMethod: consent.optInMethod,
      optInAt: consent.optInAt,
      optOutAt: consent.optOutAt,
      optOutMethod: consent.optOutMethod,
      optOutReason: consent.optOutReason,
      consentVersion: consent.consentVersion,
      messageCategories: JSON.parse(consent.messageCategories || '[]'),
      marketingConsent: consent.marketingConsent,
      marketingOptInAt: consent.marketingOptInAt,
      updatedAt: consent.updatedAt,
    };
  }
}
