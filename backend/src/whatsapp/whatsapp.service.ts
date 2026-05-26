import { Injectable, BadRequestException, NotFoundException, UnauthorizedException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { OptInDto } from './dto/opt-in.dto';
import { OptOutDto } from './dto/opt-out.dto';
import { UpdateMarketingConsentDto } from './dto/update-marketing-consent.dto';
import { TrackAnalyticsEventDto } from './dto/track-analytics-event.dto';
import { createHmac } from 'crypto';

@Injectable()
export class WhatsAppService {
  constructor(private prisma: PrismaService) {}

  // ── Consent Management ──────────────────────────────────────────

  /**
   * GET /api/whatsapp/consent?userId=xxx
   * Get consent status (parse JSON messageCategories)
   */
  async getConsent(userId: string) {
    if (!userId) {
      throw new BadRequestException('userId query parameter is required');
    }

    const consent = await this.prisma.whatsAppConsent.findUnique({
      where: { userId },
    });

    if (!consent) {
      return { consent: null, message: 'No WhatsApp consent record found for this user' };
    }

    // Parse JSON fields for client convenience
    const parsedConsent = {
      ...consent,
      messageCategories: JSON.parse(consent.messageCategories) as string[],
    };

    return { consent: parsedConsent };
  }

  /**
   * POST /api/whatsapp/consent — Opt-in
   */
  async optIn(dto: OptInDto) {
    // Verify user exists
    const user = await this.prisma.user.findUnique({ where: { id: dto.userId } });
    if (!user) {
      throw new NotFoundException('User not found');
    }

    const now = new Date();

    // Create or update WhatsAppConsent record
    const consent = await this.prisma.whatsAppConsent.upsert({
      where: { userId: dto.userId },
      update: {
        phone: dto.phone,
        optedIn: true,
        optInMethod: dto.optInMethod,
        optInAt: now,
        optOutAt: null,
        optOutMethod: null,
        optOutReason: null,
        messageCategories: JSON.stringify(dto.categories),
        marketingConsent: dto.marketingConsent ?? false,
        marketingOptInAt: dto.marketingConsent ? now : undefined,
        consentVersion: 'v1',
      },
      create: {
        userId: dto.userId,
        phone: dto.phone,
        optedIn: true,
        optInMethod: dto.optInMethod,
        optInAt: now,
        messageCategories: JSON.stringify(dto.categories),
        marketingConsent: dto.marketingConsent ?? false,
        marketingOptInAt: dto.marketingConsent ? now : undefined,
        consentVersion: 'v1',
      },
    });

    // Create WhatsAppOptIn records for each category
    for (const category of dto.categories) {
      await this.prisma.whatsAppOptIn.upsert({
        where: {
          phone_templateType: {
            phone: dto.phone,
            templateType: category,
          },
        },
        update: {
          optedIn: true,
          optedInAt: now,
        },
        create: {
          phone: dto.phone,
          templateType: category,
          optedIn: true,
          optedInAt: now,
        },
      });
    }

    // Log analytics event
    await this.prisma.whatsAppAnalytics.create({
      data: {
        event: 'whatsapp.opt_in.completed',
        userId: dto.userId,
        metadata: JSON.stringify({
          source: dto.optInMethod,
          categories: dto.categories,
          marketingConsent: dto.marketingConsent,
        }),
      },
    });

    // Parse JSON fields for response
    const parsedConsent = {
      ...consent,
      messageCategories: JSON.parse(consent.messageCategories) as string[],
    };

    return { consent: parsedConsent };
  }

  /**
   * PUT /api/whatsapp/consent — Opt-out
   */
  async optOut(dto: OptOutDto) {
    const existing = await this.prisma.whatsAppConsent.findUnique({
      where: { userId: dto.userId },
    });

    if (!existing) {
      throw new NotFoundException('No WhatsApp consent record found for this user');
    }

    const now = new Date();

    // Update WhatsAppConsent: optedIn=false, optOutAt=now, marketingConsent=false
    const updated = await this.prisma.whatsAppConsent.update({
      where: { userId: dto.userId },
      data: {
        optedIn: false,
        optOutAt: now,
        optOutMethod: dto.optOutMethod,
        optOutReason: dto.reason ?? null,
        marketingConsent: false,
        marketingOptInAt: null,
        messageCategories: JSON.stringify([]),
      },
    });

    // Delete WhatsAppOptIn records for this phone
    await this.prisma.whatsAppOptIn.deleteMany({
      where: { phone: existing.phone },
    });

    // Log analytics event
    await this.prisma.whatsAppAnalytics.create({
      data: {
        event: 'whatsapp.opt_out.requested',
        userId: dto.userId,
        metadata: JSON.stringify({
          method: dto.optOutMethod,
          reason: dto.reason ?? null,
        }),
      },
    });

    const parsedConsent = {
      ...updated,
      messageCategories: JSON.parse(updated.messageCategories) as string[],
    };

    return { consent: parsedConsent };
  }

  /**
   * PATCH /api/whatsapp/consent — Update marketing consent
   */
  async updateMarketingConsent(dto: UpdateMarketingConsentDto) {
    const existing = await this.prisma.whatsAppConsent.findUnique({
      where: { userId: dto.userId },
    });

    if (!existing) {
      throw new NotFoundException('No WhatsApp consent record found for this user');
    }

    const now = new Date();

    // Update marketing consent
    const updated = await this.prisma.whatsAppConsent.update({
      where: { userId: dto.userId },
      data: {
        marketingConsent: dto.marketingConsent,
        marketingOptInAt: dto.marketingConsent ? now : null,
      },
    });

    // If enabling marketing consent, ensure the marketing opt-in category exists
    if (dto.marketingConsent) {
      await this.prisma.whatsAppOptIn.upsert({
        where: {
          phone_templateType: {
            phone: existing.phone,
            templateType: 'marketing',
          },
        },
        update: {
          optedIn: true,
          optedInAt: now,
        },
        create: {
          phone: existing.phone,
          templateType: 'marketing',
          optedIn: true,
          optedInAt: now,
        },
      });
    } else {
      // Remove marketing opt-in category
      await this.prisma.whatsAppOptIn.deleteMany({
        where: {
          phone: existing.phone,
          templateType: 'marketing',
        },
      });
    }

    const parsedConsent = {
      ...updated,
      messageCategories: JSON.parse(updated.messageCategories) as string[],
    };

    return { consent: parsedConsent };
  }

  // ── Webhook Handling ─────────────────────────────────────────────

  /**
   * GET /api/whatsapp/webhook — Webhook verification
   */
  verifyWebhook(mode: string, token: string, challenge: string): string {
    const verifyToken = process.env.WHATSAPP_WEBHOOK_VERIFY_TOKEN ?? 'daxelo_verify_token';

    if (mode === 'subscribe' && token === verifyToken) {
      return challenge;
    }

    throw new UnauthorizedException('Invalid verification token or mode');
  }

  /**
   * POST /api/whatsapp/webhook — Incoming message handler (simplified stub)
   */
  async handleWebhook(rawBody: string, signature: string) {
    // Verify signature (simplified — in production, use proper WhatsApp Business API verification)
    const appSecret = process.env.WHATSAPP_APP_SECRET ?? '';
    if (appSecret) {
      const expectedSig = createHmac('sha256', appSecret)
        .update(rawBody)
        .digest('hex');
      if (signature !== `sha256=${expectedSig}`) {
        console.warn('[WhatsApp Webhook] Invalid signature');
        // Still return OK to prevent retries
        return { status: 'ok' };
      }
    }

    try {
      const payload = JSON.parse(rawBody);

      // Process only WhatsApp Business Account events
      if (payload.object === 'whatsapp_business_account') {
        const entries = payload.entry ?? [];

        for (const entry of entries) {
          const changes = entry.changes ?? [];

          for (const change of changes) {
            // Handle incoming messages (simplified stub)
            const messages = change.value?.messages;
            if (messages && Array.isArray(messages)) {
              for (const msg of messages) {
                console.log('[WhatsApp Webhook] Received message:', msg.messageId ?? 'unknown');
                // In a full implementation, route commands via bot-router
              }
            }

            // Handle delivery status updates (simplified stub)
            const statuses = change.value?.statuses;
            if (statuses && Array.isArray(statuses)) {
              for (const status of statuses) {
                console.log('[WhatsApp Webhook] Delivery status:', status.status ?? 'unknown');
                // In a full implementation, handle delivery status tracking
              }
            }
          }
        }
      }

      return { status: 'ok' };
    } catch (error) {
      console.error('[WhatsApp Webhook] Parse error:', error);
      // Still return OK to prevent WhatsApp from retrying
      return { status: 'ok' };
    }
  }

  // ── Analytics ────────────────────────────────────────────────────

  /**
   * GET /api/whatsapp/analytics?event=&userId=&templateId=&startDate=&endDate=&limit=100
   * Query analytics (parse JSON metadata)
   */
  async getAnalytics(params: {
    event?: string;
    userId?: string;
    templateId?: string;
    startDate?: string;
    endDate?: string;
    limit?: number;
  }) {
    const limit = params.limit ?? 100;

    // Build where clause from query params
    const where: Record<string, unknown> = {};

    if (params.event) where.event = params.event;
    if (params.userId) where.userId = params.userId;
    if (params.templateId) where.templateId = params.templateId;

    if (params.startDate || params.endDate) {
      const createdAt: Record<string, Date> = {};
      if (params.startDate) createdAt.gte = new Date(params.startDate);
      if (params.endDate) createdAt.lte = new Date(params.endDate);
      where.createdAt = createdAt;
    }

    const events = await this.prisma.whatsAppAnalytics.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      take: Math.min(limit, 1000),
    });

    // Parse JSON metadata for client convenience
    const parsedEvents = events.map((e) => ({
      ...e,
      metadata: JSON.parse(e.metadata) as Record<string, unknown>,
    }));

    return { events: parsedEvents, count: parsedEvents.length };
  }

  /**
   * POST /api/whatsapp/analytics — Track event
   */
  async trackEvent(dto: TrackAnalyticsEventDto) {
    const analyticsEvent = await this.prisma.whatsAppAnalytics.create({
      data: {
        event: dto.event,
        userId: dto.userId ?? null,
        familyId: dto.familyId ?? null,
        messageId: dto.messageId ?? null,
        templateId: dto.templateId ?? null,
        metadata: JSON.stringify(dto.metadata ?? {}),
      },
    });

    return {
      event: {
        ...analyticsEvent,
        metadata: JSON.parse(analyticsEvent.metadata) as Record<string, unknown>,
      },
    };
  }
}
