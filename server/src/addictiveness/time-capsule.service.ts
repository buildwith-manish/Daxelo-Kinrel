// server/src/addictiveness/time-capsule.service.ts
//
// A-2 Time Capsule — messages locked until a future reveal date.
//
// Lifecycle:
//   1. Family member creates a capsule via POST /addictiveness/time-capsules
//      - Sets revealAt (the future unlock date)
//      - Sets title + content (text/photo/video)
//      - Optionally sets recipientPersonId or recipientUserId
//   2. A daily cron (8am IST) checks for capsules with status='locked' AND revealAt <= now
//      - Sets status='revealed', revealedAt=now
//      - If notifyOnReveal=true, sends FCM push to the recipient (or all family members if no recipient)
//   3. When the recipient opens the capsule, status='viewed', viewedAt=now
//   4. Cancel: creator can cancel before reveal (status='cancelled')
//
// Use cases:
//   - A parent writes a letter to their child's 18th birthday
//   - A grandparent records a wedding wish for a grandchild not yet married
//   - A family member leaves a message to be opened after their passing
//
// Unlike AncestralMemory (which is about preserving the past), TimeCapsule is
// about sending a message to the FUTURE.

import {
  Injectable,
  Logger,
  ForbiddenException,
  NotFoundException,
  BadRequestException,
} from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

export interface CreateTimeCapsuleInput {
  familyId: string;
  recipientPersonId?: string;
  recipientUserId?: string;
  mediaType: 'text' | 'photo' | 'video';
  textContent?: string;
  mediaUrl?: string;
  thumbnailUrl?: string;
  title: string;
  revealAt: Date;
  revealReason?: string;
  notifyOnReveal?: boolean;
}

@Injectable()
export class TimeCapsuleService {
  private readonly logger = new Logger(TimeCapsuleService.name);

  constructor(private readonly prisma: PrismaService) {}

  /**
   * Create a new time capsule. The creator must be a family member.
   * revealAt must be in the future.
   */
  async createCapsule(input: CreateTimeCapsuleInput, creatorId: string) {
    await this.assertFamilyMember(creatorId, input.familyId);

    if (input.revealAt <= new Date()) {
      throw new BadRequestException('revealAt must be in the future');
    }

    if (input.mediaType === 'text' && !input.textContent) {
      throw new BadRequestException('textContent is required for text capsules');
    }
    if ((input.mediaType === 'photo' || input.mediaType === 'video') && !input.mediaUrl) {
      throw new BadRequestException('mediaUrl is required for photo/video capsules');
    }

    const capsule = await this.prisma.timeCapsule.create({
      data: {
        familyId: input.familyId,
        creatorId,
        recipientPersonId: input.recipientPersonId ?? null,
        recipientUserId: input.recipientUserId ?? null,
        mediaType: input.mediaType,
        textContent: input.textContent ?? null,
        mediaUrl: input.mediaUrl ?? null,
        thumbnailUrl: input.thumbnailUrl ?? null,
        title: input.title,
        revealAt: input.revealAt,
        revealReason: input.revealReason ?? null,
        notifyOnReveal: input.notifyOnReveal ?? true,
        status: 'locked',
      },
      include: {
        creator: { select: { id: true, name: true, photoThumb: true } },
        recipientPerson: { select: { id: true, name: true, photoThumb: true } },
        recipientUser: { select: { id: true, name: true, photoThumb: true } },
      },
    });

    this.logger.log(
      `TimeCapsule: created capsule "${input.title}" (id=${capsule.id}), reveals on ${input.revealAt.toISOString()}`,
    );

    return this.serializeCapsule(capsule);
  }

  /**
   * List capsules for a family.
   * Only returns REVEALED capsules for non-creators (locked capsules are private
   * to the creator until reveal time).
   */
  async listCapsules(
    userId: string,
    familyId: string,
    opts: { status?: string; limit?: number } = {},
  ) {
    await this.assertFamilyMember(userId, familyId);
    const limit = Math.min(opts.limit ?? 50, 100);

    // Non-creators can only see: revealed capsules + capsules where they're the recipient
    // Creators can see all their own capsules
    const capsules = await this.prisma.timeCapsule.findMany({
      where: {
        familyId,
        ...(opts.status ? { status: opts.status } : {}),
        OR: [
          { creatorId: userId }, // creator sees all their own
          { status: 'revealed' }, // anyone sees revealed
          { status: 'viewed' },
          { recipientUserId: userId }, // recipient sees their own (even if locked, for anticipation)
        ],
      },
      orderBy: { revealAt: 'asc' },
      take: limit,
      include: {
        creator: { select: { id: true, name: true, photoThumb: true } },
        recipientPerson: { select: { id: true, name: true, photoThumb: true } },
        recipientUser: { select: { id: true, name: true, photoThumb: true } },
      },
    });

    // For locked capsules not owned by the user, redact the content
    return capsules.map((c) => {
      if (c.status === 'locked' && c.creatorId !== userId && c.recipientUserId !== userId) {
        return this.serializeCapsule(c, /* redactContent */ true);
      }
      return this.serializeCapsule(c);
    });
  }

  /** Get capsules FOR a specific user (as recipient or creator). */
  async getCapsulesForUser(userId: string) {
    const capsules = await this.prisma.timeCapsule.findMany({
      where: {
        OR: [{ creatorId: userId }, { recipientUserId: userId }],
      },
      orderBy: { revealAt: 'asc' },
      include: {
        creator: { select: { id: true, name: true, photoThumb: true } },
        recipientPerson: { select: { id: true, name: true, photoThumb: true } },
      },
    });

    return capsules.map((c) => {
      // Redact content if locked and user is recipient (not creator)
      const redact = c.status === 'locked' && c.creatorId !== userId;
      return this.serializeCapsule(c, redact);
    });
  }

  /** Mark a capsule as viewed (when the recipient opens it after reveal). */
  async markViewed(capsuleId: string, userId: string) {
    const capsule = await this.prisma.timeCapsule.findUnique({
      where: { id: capsuleId },
      select: { id: true, status: true, recipientUserId: true, familyId: true, creatorId: true },
    });
    if (!capsule) throw new NotFoundException('Capsule not found');

    // Verify access (recipient, creator, or family member)
    if (
      capsule.recipientUserId !== userId &&
      capsule.creatorId !== userId
    ) {
      await this.assertFamilyMember(userId, capsule.familyId);
    }

    if (capsule.status !== 'revealed' && capsule.status !== 'viewed') {
      throw new BadRequestException('Capsule must be revealed before it can be viewed');
    }

    const updated = await this.prisma.timeCapsule.update({
      where: { id: capsuleId },
      data: { status: 'viewed', viewedAt: new Date() },
    });

    return { id: updated.id, status: updated.status, viewedAt: updated.viewedAt?.toISOString() };
  }

  /** Cancel a capsule (before reveal). Only the creator can cancel. */
  async cancelCapsule(capsuleId: string, userId: string) {
    const capsule = await this.prisma.timeCapsule.findUnique({
      where: { id: capsuleId },
      select: { id: true, creatorId: true, status: true },
    });
    if (!capsule) throw new NotFoundException('Capsule not found');
    if (capsule.creatorId !== userId) {
      throw new ForbiddenException('Only the creator can cancel a capsule');
    }
    if (capsule.status !== 'locked') {
      throw new BadRequestException('Only locked capsules can be cancelled');
    }

    const updated = await this.prisma.timeCapsule.update({
      where: { id: capsuleId },
      data: { status: 'cancelled', cancelledAt: new Date() },
    });

    return { id: updated.id, status: updated.status };
  }

  /**
   * Daily cron (8am IST): reveal capsules whose revealAt <= now.
   * Returns the list of newly-revealed capsules (for FCM push).
   */
  async revealDueCapsules(): Promise<
    Array<{
      capsuleId: string;
      title: string;
      recipientUserId?: string;
      familyId: string;
      creatorName: string;
    }>
  > {
    const now = new Date();
    const due = await this.prisma.timeCapsule.findMany({
      where: {
        status: 'locked',
        revealAt: { lte: now },
      },
      include: {
        creator: { select: { id: true, name: true } },
      },
    });

    const revealed: Array<{
      capsuleId: string;
      title: string;
      recipientUserId?: string;
      familyId: string;
      creatorName: string;
    }> = [];

    for (const capsule of due) {
      await this.prisma.timeCapsule.update({
        where: { id: capsule.id },
        data: {
          status: 'revealed',
          revealedAt: now,
          notifiedAt: capsule.notifyOnReveal ? now : null,
        },
      });

      revealed.push({
        capsuleId: capsule.id,
        title: capsule.title,
        recipientUserId: capsule.recipientUserId ?? undefined,
        familyId: capsule.familyId,
        creatorName: capsule.creator?.name ?? 'A family member',
      });

      this.logger.log(
        `TimeCapsule: revealed "${capsule.title}" (id=${capsule.id})`,
      );
    }

    this.logger.log(`TimeCapsule: revealed ${revealed.length} capsules today`);
    return revealed;
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

  private serializeCapsule(c: any, redactContent: boolean = false) {
    return {
      id: c.id,
      familyId: c.familyId,
      creatorId: c.creatorId,
      creator: c.creator
        ? { id: c.creator.id, name: c.creator.name, photoThumb: c.creator.photoThumb }
        : null,
      recipientPersonId: c.recipientPersonId,
      recipientPerson: c.recipientPerson
        ? { id: c.recipientPerson.id, name: c.recipientPerson.name, photoThumb: c.recipientPerson.photoThumb }
        : null,
      recipientUserId: c.recipientUserId,
      recipientUser: c.recipientUser
        ? { id: c.recipientUser.id, name: c.recipientUser.name, photoThumb: c.recipientUser.photoThumb }
        : null,
      mediaType: c.mediaType,
      // Redact content for locked capsules when the viewer isn't the creator
      textContent: redactContent ? null : c.textContent,
      mediaUrl: redactContent ? null : c.mediaUrl,
      thumbnailUrl: redactContent ? null : c.thumbnailUrl,
      title: c.title,
      revealAt: c.revealAt.toISOString(),
      revealReason: c.revealReason,
      status: c.status,
      revealedAt: c.revealedAt?.toISOString() ?? null,
      viewedAt: c.viewedAt?.toISOString() ?? null,
      notifyOnReveal: c.notifyOnReveal,
      createdAt: c.createdAt.toISOString(),
      isLocked: c.status === 'locked',
      // For locked capsules, show a countdown instead of content
      countdownDays: c.status === 'locked'
        ? Math.max(0, Math.ceil((c.revealAt.getTime() - Date.now()) / (1000 * 60 * 60 * 24)))
        : 0,
    };
  }
}
