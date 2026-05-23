import {
  Injectable,
  NotFoundException,
  BadRequestException,
  Logger,
} from '@nestjs/common';
import { PrismaService } from '@/common/prisma/prisma.service';
import { ConfigService } from '@nestjs/config';
import { createHmac } from 'crypto';

@Injectable()
export class WhatsAppService {
  private readonly logger = new Logger(WhatsAppService.name);

  private readonly verifyToken: string;
  private readonly appSecret: string;

  constructor(
    private readonly prisma: PrismaService,
    private readonly configService: ConfigService,
  ) {
    this.verifyToken = this.configService.get<string>('WHATSAPP_VERIFY_TOKEN', 'kinrel_verify_token');
    this.appSecret = this.configService.get<string>('WHATSAPP_APP_SECRET', '');
  }

  // ── Webhook Verification ──────────────────────────────────────────

  verifyWebhook(mode: string, token: string): boolean {
    return mode === 'subscribe' && token === this.verifyToken;
  }

  // ── Verify HMAC Signature ─────────────────────────────────────────

  verifySignature(payload: string, signature: string): boolean {
    if (!this.appSecret) return true; // Skip if no secret configured
    const expected = createHmac('sha256', this.appSecret).update(payload).digest('hex');
    return signature === `sha256=${expected}`;
  }

  // ── Process Incoming Webhook ──────────────────────────────────────

  async processWebhook(payload: any): Promise<void> {
    if (payload.object !== 'whatsapp_business_account') return;

    const entries = payload.entry ?? [];
    for (const entry of entries) {
      const changes = entry.changes ?? [];

      for (const change of changes) {
        // Handle incoming messages
        const messages = change.value?.messages;
        if (messages && Array.isArray(messages)) {
          for (const msg of messages) {
            try {
              // Log the incoming message as an analytics event
              await this.prisma.whatsAppAnalytics.create({
                data: {
                  event: 'whatsapp.message.received',
                  userId: msg.from ?? null,
                  messageId: msg.id ?? null,
                  metadata: JSON.stringify(msg),
                },
              });
            } catch (error) {
              this.logger.error(`Bot handler error for message: ${msg.id}`, error);
            }
          }
        }

        // Handle delivery status updates
        const statuses = change.value?.statuses;
        if (statuses && Array.isArray(statuses)) {
          for (const status of statuses) {
            try {
              await this.prisma.whatsAppAnalytics.create({
                data: {
                  event: `whatsapp.message.${status.status}`,
                  messageId: status.id ?? null,
                  metadata: JSON.stringify(status),
                },
              });
            } catch (error) {
              this.logger.error('Delivery status handler error:', error);
            }
          }
        }
      }
    }
  }

  // ── Get Analytics ─────────────────────────────────────────────────

  async getAnalytics(options: {
    event?: string;
    userId?: string;
    templateId?: string;
    startDate?: string;
    endDate?: string;
    limit?: number;
  }) {
    const where: Record<string, unknown> = {};

    if (options.event) where.event = options.event;
    if (options.userId) where.userId = options.userId;
    if (options.templateId) where.templateId = options.templateId;

    if (options.startDate || options.endDate) {
      const createdAt: Record<string, Date> = {};
      if (options.startDate) createdAt.gte = new Date(options.startDate);
      if (options.endDate) createdAt.lte = new Date(options.endDate);
      where.createdAt = createdAt;
    }

    const limit = Math.min(options.limit ?? 100, 1000);

    const events = await this.prisma.whatsAppAnalytics.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      take: limit,
    });

    const parsedEvents = events.map((e) => ({
      ...e,
      metadata: JSON.parse(e.metadata) as Record<string, unknown>,
    }));

    return { events: parsedEvents, count: parsedEvents.length };
  }

  // ── Log Analytics Event ───────────────────────────────────────────

  async logAnalyticsEvent(body: {
    event: string;
    userId?: string;
    familyId?: string;
    messageId?: string;
    templateId?: string;
    metadata?: Record<string, unknown>;
  }) {
    if (!body.event) {
      throw new BadRequestException('event is required');
    }

    const analyticsEvent = await this.prisma.whatsAppAnalytics.create({
      data: {
        event: body.event,
        userId: body.userId ?? null,
        familyId: body.familyId ?? null,
        messageId: body.messageId ?? null,
        templateId: body.templateId ?? null,
        metadata: JSON.stringify(body.metadata ?? {}),
      },
    });

    return {
      event: {
        ...analyticsEvent,
        metadata: JSON.parse(analyticsEvent.metadata) as Record<string, unknown>,
      },
    };
  }

  // ── Get Consent ───────────────────────────────────────────────────

  async getConsent(userId: string) {
    if (!userId) {
      throw new BadRequestException('userId query parameter is required');
    }

    const consent = await this.prisma.whatsAppConsent.findUnique({
      where: { userId },
    });

    if (!consent) {
      return {
        consent: null,
        message: 'No WhatsApp consent record found for this user',
      };
    }

    const parsedConsent = {
      ...consent,
      messageCategories: JSON.parse(consent.messageCategories) as string[],
    };

    return { consent: parsedConsent };
  }

  // ── Opt In ────────────────────────────────────────────────────────

  async optIn(body: {
    userId: string;
    phone: string;
    optInMethod: string;
    categories: string[];
    marketingConsent: boolean;
  }) {
    if (!body.userId || !body.phone || !body.optInMethod) {
      throw new BadRequestException('userId, phone, and optInMethod are required');
    }

    const user = await this.prisma.user.findUnique({ where: { id: body.userId } });
    if (!user) throw new NotFoundException('User not found');

    const now = new Date();

    const consent = await this.prisma.whatsAppConsent.upsert({
      where: { userId: body.userId },
      update: {
        phone: body.phone,
        optedIn: true,
        optInMethod: body.optInMethod,
        optInAt: now,
        optOutAt: null,
        optOutMethod: null,
        optOutReason: null,
        messageCategories: JSON.stringify(body.categories),
        marketingConsent: body.marketingConsent ?? false,
        marketingOptInAt: body.marketingConsent ? now : undefined,
        consentVersion: 'v1',
      },
      create: {
        userId: body.userId,
        phone: body.phone,
        optedIn: true,
        optInMethod: body.optInMethod,
        optInAt: now,
        messageCategories: JSON.stringify(body.categories),
        marketingConsent: body.marketingConsent ?? false,
        marketingOptInAt: body.marketingConsent ? now : undefined,
        consentVersion: 'v1',
      },
    });

    // Create WhatsAppOptIn records for each category
    for (const category of body.categories) {
      await this.prisma.whatsAppOptIn.upsert({
        where: { phone_templateType: { phone: body.phone, templateType: category } },
        update: { optedIn: true, optedInAt: now },
        create: { phone: body.phone, templateType: category, optedIn: true, optedInAt: now },
      });
    }

    // Log analytics event
    await this.prisma.whatsAppAnalytics.create({
      data: {
        event: 'whatsapp.opt_in.completed',
        userId: body.userId,
        metadata: JSON.stringify({
          source: body.optInMethod,
          categories: body.categories,
          marketingConsent: body.marketingConsent,
        }),
      },
    });

    const parsedConsent = {
      ...consent,
      messageCategories: JSON.parse(consent.messageCategories) as string[],
    };

    return { consent: parsedConsent };
  }

  // ── Opt Out ───────────────────────────────────────────────────────

  async optOut(body: { userId: string; optOutMethod: string; reason?: string }) {
    if (!body.userId || !body.optOutMethod) {
      throw new BadRequestException('userId and optOutMethod are required');
    }

    const existing = await this.prisma.whatsAppConsent.findUnique({
      where: { userId: body.userId },
    });

    if (!existing) {
      throw new NotFoundException('No WhatsApp consent record found for this user');
    }

    const now = new Date();

    const updated = await this.prisma.whatsAppConsent.update({
      where: { userId: body.userId },
      data: {
        optedIn: false,
        optOutAt: now,
        optOutMethod: body.optOutMethod,
        optOutReason: body.reason ?? null,
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
        userId: body.userId,
        metadata: JSON.stringify({ method: body.optOutMethod, reason: body.reason ?? null }),
      },
    });

    const parsedConsent = {
      ...updated,
      messageCategories: JSON.parse(updated.messageCategories) as string[],
    };

    return { consent: parsedConsent };
  }

  // ── Marketing Toggle ──────────────────────────────────────────────

  async marketingToggle(body: { userId: string; marketingConsent: boolean; method: string }) {
    if (!body.userId || typeof body.marketingConsent !== 'boolean') {
      throw new BadRequestException('userId and marketingConsent (boolean) are required');
    }

    const existing = await this.prisma.whatsAppConsent.findUnique({
      where: { userId: body.userId },
    });

    if (!existing) {
      throw new NotFoundException('No WhatsApp consent record found for this user');
    }

    const now = new Date();

    const updated = await this.prisma.whatsAppConsent.update({
      where: { userId: body.userId },
      data: {
        marketingConsent: body.marketingConsent,
        marketingOptInAt: body.marketingConsent ? now : null,
      },
    });

    // Handle per-template opt-in for marketing
    if (body.marketingConsent) {
      await this.prisma.whatsAppOptIn.upsert({
        where: { phone_templateType: { phone: existing.phone, templateType: 'marketing' } },
        update: { optedIn: true, optedInAt: now },
        create: { phone: existing.phone, templateType: 'marketing', optedIn: true, optedInAt: now },
      });
    } else {
      await this.prisma.whatsAppOptIn.deleteMany({
        where: { phone: existing.phone, templateType: 'marketing' },
      });
    }

    const parsedConsent = {
      ...updated,
      messageCategories: JSON.parse(updated.messageCategories) as string[],
    };

    return { consent: parsedConsent };
  }
}
