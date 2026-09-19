import {
  Injectable,
  ForbiddenException,
  NotFoundException,
  Logger,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { AddReactionDto, RemoveReactionDto } from './dto/chat.dto';

/**
 * ChatService — family group chat persistence + read receipts + reactions.
 *
 * Backed by the `ChatMessage`, `ChatReaction`, `ChatReadReceipt`, and
 * `ChatTypingStatus` tables that already exist in Supabase. The Flutter app
 * also reads/writes these tables directly via Supabase RPCs + Realtime; the
 * NestJS service here is the Socket.IO-friendly path that the new
 * `ChatGateway` uses, and it keeps the denormalized `readBy` / `readAt`
 * cache columns in sync with the per-row `ChatReadReceipt` table so both
 * clients see consistent state.
 */
@Injectable()
export class ChatService {
  private readonly logger = new Logger(ChatService.name);

  constructor(private readonly prisma: PrismaService) {}

  /** Throws ForbiddenException if the user is not a member of the family. */
  private async assertMember(familyId: string, userId: string) {
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
    });
    if (!membership) {
      throw new ForbiddenException('Not a member of this family');
    }
    return membership;
  }

  /** Resolve the User's display name + initials for the chat message row. */
  private async resolveSender(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        name: true,
        username: true,
        avatarUrl: true,
      },
    });
    if (!user) {
      throw new NotFoundException(`User ${userId} not found`);
    }
    const displayName = user.name || user.username || 'Unknown';
    const initials = displayName
      .split(/\s+/)
      .filter(Boolean)
      .slice(0, 2)
      .map((s) => s[0]?.toUpperCase() ?? '')
      .join('');
    return { displayName, initials };
  }

  /**
   * List chat messages for a family, newest first, with pagination.
   * Includes reactions and read receipts so the client can render emoji
   * counts and read-state checkmarks without a second round-trip.
   */
  async listMessages(
    familyId: string,
    userId: string,
    limit: number = 50,
    before?: string,
  ) {
    await this.assertMember(familyId, userId);

    const where: Record<string, unknown> = {
      familyId,
      isDeletedForEveryone: false,
    };
    if (before) {
      where.createdAt = { lt: new Date(before) };
    }

    return this.prisma.chatMessage.findMany({
      where,
      orderBy: { createdAt: 'desc' },
      take: Math.min(limit, 200),
      include: {
        reactions: true,
      },
    });
  }

  /**
   * Persist a new chat message. Called from the ChatGateway on 'sendMessage'.
   * The gateway is responsible for emitting the 'messageReceived' event to
   * the family room after this returns.
   */
  async sendMessage(
    familyId: string,
    userId: string,
    content: string,
    opts: {
      messageType?: string;
      replyToId?: string;
      senderPersonId?: string;
      senderInitials?: string;
      mediaUrl?: string;
      mediaType?: string;
    } = {},
  ) {
    await this.assertMember(familyId, userId);
    const { displayName, initials } = await this.resolveSender(userId);

    // If replyToId given, fetch parent for denormalized reply fields.
    let replyToContent: string | null = null;
    let replyToSenderName: string | null = null;
    if (opts.replyToId) {
      const parent = await this.prisma.chatMessage.findUnique({
        where: { id: opts.replyToId },
        select: { content: true, senderName: true, familyId: true },
      });
      if (!parent) {
        throw new NotFoundException('Reply-to message not found');
      }
      if (parent.familyId !== familyId) {
        throw new ForbiddenException('Reply-to message belongs to a different family');
      }
      replyToContent = parent.content;
      replyToSenderName = parent.senderName;
    }

    // Generate a stable ID. The existing Supabase `fn_chatmessage_gen_id`
    // RPC uses a pattern like `cm_<timestamp>_<random>`; we replicate it
    // here so IDs are unique across both NestJS and Supabase-RPC writes.
    const id = `cm_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;

    return this.prisma.chatMessage.create({
      data: {
        id,
        familyId,
        senderId: userId,
        senderPersonId: opts.senderPersonId ?? null,
        senderName: displayName,
        senderInitials: opts.senderInitials ?? initials,
        content,
        messageType: opts.messageType ?? 'text',
        replyToId: opts.replyToId ?? null,
        replyToContent,
        replyToSenderName,
        mediaUrl: opts.mediaUrl ?? null,
        mediaType: opts.mediaType ?? null,
        messageStatus: 'sent',
        readBy: [], // no readers yet
        readAt: null,
        notified: false,
      },
      include: { reactions: true },
    });
  }

  /**
   * Mark a single message (or all unread messages in the family) as read
   * by `userId`. Updates both the per-row `ChatReadReceipt` table (source
   * of truth) and the denormalized `readBy` / `readAt` cache on the
   * message. Returns the list of messageIds that were newly marked read
   * so the gateway can emit a `readReceipt` event to each sender.
   *
   * The sender's own messages are skipped — you can't "read" your own
   * message.
   */
  async markAsRead(
    familyId: string,
    userId: string,
    messageId?: string,
  ): Promise<{
    markedReadIds: string[];
    senderIds: string[];
  }> {
    await this.assertMember(familyId, userId);

    // Find unread messages NOT sent by this user.
    const where: Record<string, unknown> = {
      familyId,
      senderId: { not: userId },
      isDeletedForEveryone: false,
      readBy: { hasNot: userId }, // not already in readBy array
    };
    if (messageId) {
      where.id = messageId;
    }

    const unread = await this.prisma.chatMessage.findMany({
      where,
      select: { id: true, senderId: true },
    });

    if (unread.length === 0) {
      return { markedReadIds: [], senderIds: [] };
    }

    const now = new Date();
    const ids = unread.map((m) => m.id);

    // 1. Insert ChatReadReceipt rows (skip duplicates via onConflict).
    // Prisma doesn't have native upsertMany, so we use createMany with
    // skipDuplicates — this is a Postgres-level INSERT ... ON CONFLICT
    // DO NOTHING, which is exactly what we want.
    await this.prisma.chatReadReceipt.createMany({
      data: ids.map((id) => ({
        id: `crr_${id}_${userId}`,
        messageId: id,
        userId,
        readAt: now,
      })),
      skipDuplicates: true,
    });

    // 2. Update the denormalized readBy/readAt cache on each message.
    // We do this per-message because Prisma doesn't support array_append
    // in updateMany. For large batches this is N queries; acceptable
    // because typical markAsRead is for one message or the unread set
    // since last connect (usually < 50).
    await Promise.all(
      ids.map((id) =>
        this.prisma.chatMessage.update({
          where: { id },
          data: {
            readBy: { push: userId },
            readAt: now,
            // Also flip isRead boolean + messageStatus for backward compat
            // with clients that only check the boolean.
            isRead: true,
            messageStatus: 'read',
            updatedAt: now,
          },
        }),
      ),
    );

    // Unique sender IDs so the gateway can emit one readReceipt per sender.
    const senderIds = [...new Set(unread.map((m) => m.senderId))];

    this.logger.debug(
      `markAsRead: ${ids.length} message(s) marked read for user ${userId} in family ${familyId}`,
    );

    return { markedReadIds: ids, senderIds };
  }

  // ── Typing indicator persistence ──────────────────────────────────────
  //
  // The ChatTypingStatus table is the source of truth for "who is typing"
  // that survives a client refresh. The gateway also broadcasts a real-time
  // 'userTyping' / 'userStoppedTyping' event so clients don't have to poll.
  // The Flutter app polls ChatTypingStatus with a 5-second freshness window
  // as a fallback when a socket event is missed.

  async setTypingStatus(
    familyId: string,
    userId: string,
    isTyping: boolean,
  ): Promise<void> {
    await this.assertMember(familyId, userId);
    const id = `cts_${familyId}_${userId}`;
    await this.prisma.chatTypingStatus.upsert({
      where: { id },
      create: { id, familyId, userId, isTyping },
      update: { isTyping, updatedAt: new Date() },
    });
  }

  async getTypingUsers(familyId: string, excludeUserId: string) {
    // Only return typing statuses updated within the last 5 seconds —
    // stale rows are treated as "stopped typing".
    const fiveSecondsAgo = new Date(Date.now() - 5_000);
    const rows = await this.prisma.chatTypingStatus.findMany({
      where: {
        familyId,
        isTyping: true,
        updatedAt: { gt: fiveSecondsAgo },
        userId: { not: excludeUserId },
      },
      select: { userId: true, updatedAt: true },
    });
    // Resolve display names for the typing users.
    if (rows.length === 0) return [];
    const users = await this.prisma.user.findMany({
      where: { id: { in: rows.map((r) => r.userId) } },
      select: { id: true, name: true, username: true },
    });
    return rows.map((r) => {
      const u = users.find((x) => x.id === r.userId);
      return {
        userId: r.userId,
        name: u?.name || u?.username || 'Unknown',
        updatedAt: r.updatedAt,
      };
    });
  }

  // ── Reactions ────────────────────────────────────────────────────────
  //
  // Reactions are unique per (messageId, userId, emoji) so one user can
  // leave multiple different emojis on the same message but cannot leave
  // the same emoji twice. Toggle semantics: if the (user, emoji) row
  // already exists, remove it; otherwise create it.

  async addReaction(
    familyId: string,
    userId: string,
    dto: AddReactionDto,
  ): Promise<{ action: 'added' | 'alreadyExists'; reactionId: string }> {
    await this.assertMember(familyId, userId);

    // Verify the message exists + belongs to this family.
    const msg = await this.prisma.chatMessage.findUnique({
      where: { id: dto.messageId },
      select: { familyId: true },
    });
    if (!msg) throw new NotFoundException('Message not found');
    if (msg.familyId !== familyId) {
      throw new ForbiddenException('Message belongs to a different family');
    }

    const id = `cr_${dto.messageId}_${userId}_${dto.emoji}`;
    try {
      await this.prisma.chatReaction.create({
        data: {
          id,
          messageId: dto.messageId,
          userId,
          emoji: dto.emoji,
        },
      });
      return { action: 'added', reactionId: id };
    } catch (err: any) {
      // Prisma throws P2002 on unique-constraint violation — the reaction
      // already exists. Treat as idempotent success.
      if (err?.code === 'P2002') {
        return { action: 'alreadyExists', reactionId: id };
      }
      throw err;
    }
  }

  async removeReaction(
    familyId: string,
    userId: string,
    dto: RemoveReactionDto,
  ): Promise<{ deleted: boolean }> {
    await this.assertMember(familyId, userId);
    const result = await this.prisma.chatReaction.deleteMany({
      where: {
        messageId: dto.messageId,
        userId,
        emoji: dto.emoji,
      },
    });
    return { deleted: result.count > 0 };
  }

  /**
   * Get aggregated reaction counts for a message. Returns an array of
   * { emoji, count, userIds[] } sorted by count descending. The Flutter
   * client renders these as chips under the message bubble.
   */
  async getReactionCounts(messageId: string) {
    const reactions = await this.prisma.chatReaction.findMany({
      where: { messageId },
      select: { emoji: true, userId: true },
    });
    const grouped = new Map<string, string[]>();
    for (const r of reactions) {
      const arr = grouped.get(r.emoji) ?? [];
      arr.push(r.userId);
      grouped.set(r.emoji, arr);
    }
    return Array.from(grouped.entries())
      .map(([emoji, userIds]) => ({ emoji, count: userIds.length, userIds }))
      .sort((a, b) => b.count - a.count);
  }
}
