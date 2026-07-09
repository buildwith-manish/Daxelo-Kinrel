// server/src/addictiveness/blessing-chain.service.ts
//
// A-1 Blessing Chain — elder blessings scheduled for delivery on birthdays/festivals.
//
// Lifecycle:
//   1. Elder (or family member on their behalf) records a blessing via POST /addictiveness/blessings
//      - Sets triggerType (birthday | festival | anniversary | custom)
//      - Sets triggerDate (the delivery date)
//      - Sets recipientPersonId or recipientUserId
//      - Optionally isRecurring=true (re-deliver every year)
//   2. A daily cron (8am IST) checks for blessings with status='pending' AND triggerDate <= today
//      - For each, sends an FCM push to the recipient
//      - Sets status='delivered', deliveredAt=now
//      - If isRecurring=true, creates a NEW blessing row for next year's triggerDate
//   3. When the recipient opens the blessing, status='viewed', viewedAt=now
//   4. Cancel: elder or family can cancel before delivery (status='cancelled')
//
// Why this is addictively powerful:
//   - Receiving a blessing from Dadi on your birthday, in HER VOICE, is emotionally
//     devastating in the best way. You will open the app every birthday for the rest
//     of your life.
//   - Recurring blessings mean the elder "lives on" through the blessing chain even
//     after they pass — their great-grandchildren receive blessings from someone they
//     never met but who loved them.

import {
  Injectable,
  Logger,
  ForbiddenException,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

export interface CreateBlessingInput {
  familyId: string;
  elderPersonId: string;
  elderUserId?: string;
  recipientPersonId?: string;
  recipientUserId?: string;
  mediaType: 'text' | 'audio';
  textContent?: string;
  mediaUrl?: string;
  durationSec?: number;
  triggerType: 'birthday' | 'festival' | 'anniversary' | 'custom';
  triggerDate: Date; // the delivery date
  festivalKey?: string;
  language?: string;
  isRecurring?: boolean;
}

@Injectable()
export class BlessingChainService {
  private readonly logger = new Logger(BlessingChainService.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Create a new blessing. The creator must be a family member.
   * If mediaType='text', textContent is required.
   * If mediaType='audio', mediaUrl is required.
   * Either recipientPersonId or recipientUserId must be set.
   */
  async createBlessing(input: CreateBlessingInput, creatorUserId: string) {
    // Verify family membership
    await this.assertFamilyMember(creatorUserId, input.familyId);

    // Validate content
    if (input.mediaType === 'text' && !input.textContent) {
      throw new BadRequestException('textContent is required for text blessings');
    }
    if (input.mediaType === 'audio' && !input.mediaUrl) {
      throw new BadRequestException('mediaUrl is required for audio blessings');
    }
    if (!input.recipientPersonId && !input.recipientUserId) {
      throw new BadRequestException(
        'Either recipientPersonId or recipientUserId must be set',
      );
    }

    // Verify elderPersonId belongs to this family
    const elder = await this.prisma.person.findUnique({
      where: { id: input.elderPersonId },
      select: { familyId: true, deletedAt: true },
    });
    if (!elder || elder.deletedAt) {
      throw new NotFoundException('Elder person not found');
    }
    if (elder.familyId !== input.familyId) {
      throw new ForbiddenException('Elder person is not in this family');
    }

    const blessing = await this.prisma.blessingChain.create({
      data: {
        familyId: input.familyId,
        elderPersonId: input.elderPersonId,
        elderUserId: input.elderUserId ?? null,
        recipientPersonId: input.recipientPersonId ?? null,
        recipientUserId: input.recipientUserId ?? null,
        mediaType: input.mediaType,
        textContent: input.textContent ?? null,
        mediaUrl: input.mediaUrl ?? null,
        durationSec: input.durationSec ?? 0,
        triggerType: input.triggerType,
        triggerDate: input.triggerDate,
        festivalKey: input.festivalKey ?? null,
        language: input.language ?? 'en',
        isRecurring: input.isRecurring ?? false,
        status: 'pending',
      },
      include: {
        elderPerson: { select: { id: true, name: true, photoThumb: true } },
        recipientPerson: { select: { id: true, name: true, photoThumb: true } },
        recipientUser: { select: { id: true, name: true, photoThumb: true } },
      },
    });

    this.logger.log(
      `BlessingChain: created blessing ${blessing.id} from elder ${input.elderPersonId} → recipient ${input.recipientPersonId ?? input.recipientUserId} (trigger=${input.triggerType} on ${input.triggerDate.toISOString().slice(0, 10)})`,
    );

    return this.serializeBlessing(blessing);
  }

  /** List blessings for a family. Optional filter: status, elderPersonId, recipientUserId. */
  async listBlessings(
    userId: string,
    familyId: string,
    opts: {
      status?: string;
      elderPersonId?: string;
      recipientUserId?: string;
      limit?: number;
    } = {},
  ) {
    await this.assertFamilyMember(userId, familyId);

    const limit = Math.min(opts.limit ?? 50, 100);
    const blessings = await this.prisma.blessingChain.findMany({
      where: {
        familyId,
        ...(opts.status ? { status: opts.status } : {}),
        ...(opts.elderPersonId ? { elderPersonId: opts.elderPersonId } : {}),
        ...(opts.recipientUserId ? { recipientUserId: opts.recipientUserId } : {}),
      },
      orderBy: { triggerDate: 'asc' },
      take: limit,
      include: {
        elderPerson: { select: { id: true, name: true, photoThumb: true } },
        recipientPerson: { select: { id: true, name: true, photoThumb: true } },
        recipientUser: { select: { id: true, name: true, photoThumb: true } },
      },
    });

    return blessings.map((b) => this.serializeBlessing(b));
  }

  /** Get blessings FOR a specific user (as recipient). */
  async getBlessingsForUser(userId: string) {
    const blessings = await this.prisma.blessingChain.findMany({
      where: {
        OR: [{ recipientUserId: userId }],
        status: { in: ['delivered', 'viewed'] },
      },
      orderBy: { deliveredAt: 'desc' },
      include: {
        elderPerson: { select: { id: true, name: true, photoThumb: true } },
      },
    });
    return blessings.map((b) => this.serializeBlessing(b));
  }

  /** Mark a blessing as viewed (when the recipient opens it). */
  async markViewed(blessingId: string, userId: string) {
    const blessing = await this.prisma.blessingChain.findUnique({
      where: { id: blessingId },
      select: { id: true, recipientUserId: true, status: true, familyId: true },
    });
    if (!blessing) throw new NotFoundException('Blessing not found');

    // Only the recipient can mark as viewed (or a family member if recipient is a Person without a User)
    if (blessing.recipientUserId && blessing.recipientUserId !== userId) {
      await this.assertFamilyMember(userId, blessing.familyId);
    }

    if (blessing.status !== 'delivered' && blessing.status !== 'viewed') {
      throw new BadRequestException('Blessing must be delivered before it can be viewed');
    }

    const updated = await this.prisma.blessingChain.update({
      where: { id: blessingId },
      data: {
        status: 'viewed',
        viewedAt: new Date(),
      },
    });

    return { id: updated.id, status: updated.status, viewedAt: updated.viewedAt?.toISOString() };
  }

  /** Cancel a blessing (before delivery). */
  async cancelBlessing(blessingId: string, userId: string, reason?: string) {
    const blessing = await this.prisma.blessingChain.findUnique({
      where: { id: blessingId },
      select: { id: true, familyId: true, status: true, elderUserId: true },
    });
    if (!blessing) throw new NotFoundException('Blessing not found');
    await this.assertFamilyMember(userId, blessing.familyId);

    if (blessing.status !== 'pending') {
      throw new BadRequestException('Only pending blessings can be cancelled');
    }

    const updated = await this.prisma.blessingChain.update({
      where: { id: blessingId },
      data: {
        status: 'cancelled',
        cancelledAt: new Date(),
        cancelledReason: reason,
      },
    });

    return { id: updated.id, status: updated.status };
  }

  /**
   * Daily cron job (8am IST): deliver blessings whose triggerDate <= today.
   * For each due blessing:
   *   1. Set status='delivered', deliveredAt=now
   *   2. If isRecurring=true, create a NEW blessing for next year's triggerDate
   * Returns the list of delivered blessings (for FCM push).
   */
  async deliverDueBlessings(): Promise<
    Array<{ blessingId: string; recipientUserId?: string; recipientPersonId?: string; elderName: string }>
  > {
    const today = new Date();
    today.setUTCHours(0, 0, 0, 0);

    const due = await this.prisma.blessingChain.findMany({
      where: {
        status: 'pending',
        triggerDate: { lte: today },
      },
      include: {
        elderPerson: { select: { id: true, name: true } },
      },
    });

    const delivered: Array<{
      blessingId: string;
      recipientUserId?: string;
      recipientPersonId?: string;
      elderName: string;
    }> = [];

    for (const blessing of due) {
      await this.prisma.blessingChain.update({
        where: { id: blessing.id },
        data: {
          status: 'delivered',
          deliveredAt: new Date(),
          lastDeliveredAt: new Date(),
        },
      });

      // If recurring, create next year's blessing
      if (blessing.isRecurring) {
        const nextTriggerDate = new Date(blessing.triggerDate);
        nextTriggerDate.setUTCFullYear(nextTriggerDate.getUTCFullYear() + 1);

        await this.prisma.blessingChain.create({
          data: {
            familyId: blessing.familyId,
            elderPersonId: blessing.elderPersonId,
            elderUserId: blessing.elderUserId,
            recipientPersonId: blessing.recipientPersonId,
            recipientUserId: blessing.recipientUserId,
            mediaType: blessing.mediaType,
            textContent: blessing.textContent,
            mediaUrl: blessing.mediaUrl,
            durationSec: blessing.durationSec,
            triggerType: blessing.triggerType,
            triggerDate: nextTriggerDate,
            festivalKey: blessing.festivalKey,
            language: blessing.language,
            isRecurring: true,
            status: 'pending',
          },
        });
      }

      delivered.push({
        blessingId: blessing.id,
        recipientUserId: blessing.recipientUserId ?? undefined,
        recipientPersonId: blessing.recipientPersonId ?? undefined,
        elderName: blessing.elderPerson?.name ?? 'A family elder',
      });

      this.logger.log(
        `BlessingChain: delivered blessing ${blessing.id} from ${blessing.elderPerson?.name}`,
      );
    }

    this.logger.log(`BlessingChain: delivered ${delivered.length} blessings today`);
    return delivered;
  }

  // ────────────────────────────────────────────────────────────────────────
  // Helpers
  // ────────────────────────────────────────────────────────────────────────

  private async assertFamilyMember(userId: string, familyId: string): Promise<void> {
    const fm = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
      select: { id: true },
    });
    if (!fm) {
      throw new ForbiddenException('User is not a member of this family');
    }
  }

  private serializeBlessing(b: any) {
    return {
      id: b.id,
      familyId: b.familyId,
      elderPersonId: b.elderPersonId,
      elderPerson: b.elderPerson
        ? { id: b.elderPerson.id, name: b.elderPerson.name, photoThumb: b.elderPerson.photoThumb }
        : null,
      elderUserId: b.elderUserId,
      recipientPersonId: b.recipientPersonId,
      recipientPerson: b.recipientPerson
        ? { id: b.recipientPerson.id, name: b.recipientPerson.name, photoThumb: b.recipientPerson.photoThumb }
        : null,
      recipientUserId: b.recipientUserId,
      recipientUser: b.recipientUser
        ? { id: b.recipientUser.id, name: b.recipientUser.name, photoThumb: b.recipientUser.photoThumb }
        : null,
      mediaType: b.mediaType,
      textContent: b.textContent,
      mediaUrl: b.mediaUrl,
      durationSec: b.durationSec,
      triggerType: b.triggerType,
      triggerDate: b.triggerDate.toISOString().slice(0, 10),
      festivalKey: b.festivalKey,
      language: b.language,
      status: b.status,
      deliveredAt: b.deliveredAt?.toISOString() ?? null,
      viewedAt: b.viewedAt?.toISOString() ?? null,
      isRecurring: b.isRecurring,
      lastDeliveredAt: b.lastDeliveredAt?.toISOString() ?? null,
      createdAt: b.createdAt.toISOString(),
    };
  }
}
