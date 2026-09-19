import {
  Injectable,
  ForbiddenException,
  NotFoundException,
  Logger,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { StreakService } from './streak.service';
import { ChatAnalyticsService } from '../analytics/chat-analytics.service';
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

  constructor(
    private readonly prisma: PrismaService,
    private readonly streakService: StreakService,
    private readonly analyticsService: ChatAnalyticsService,
  ) {}

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
      /// Feature 4: client-generated idempotency key. If provided AND a
      /// message with this ID already exists, the server returns the
      /// existing message instead of creating a duplicate. This makes
      /// retries after reconnect safe (the client sends the same ID
      /// twice; the server deduplicates).
      clientMessageId?: string;
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
    //
    // Feature 4: if the client provides a clientMessageId (idempotency
    // key), use it as the message ID. This makes retries safe — if the
    // client sends the same clientMessageId twice (e.g. after reconnect),
    // the second insert fails with P2002 + we return the existing message.
    const id = opts.clientMessageId ?? `cm_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;

    // Feature 4: idempotency check — if a message with this ID already
    // exists (retry after reconnect), return it instead of creating a
    // duplicate. This is the server-side dedup that makes the offline
    // sync queue safe to replay.
    const existing = await this.prisma.chatMessage.findUnique({
      where: { id },
      include: { reactions: true },
    });
    if (existing) {
      this.logger.debug(
        `Idempotent retry: returning existing message ${id} (duplicate send suppressed)`,
      );
      return existing;
    }

    const message = await this.prisma.chatMessage.create({
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

    // ── Feature 1: Analytics instrumentation ────────────────────────────
    // Fire-and-forget. Track the message_sent event + voice_note_sent if
    // applicable. Also check if this is the first-ever message in the chat
    // (for the onboarding flow) — we do this via a count query.
    this.analyticsService
      .trackMessageSent(userId, familyId, id, {
        messageType: opts.messageType ?? 'text',
        hasReply: !!opts.replyToId,
        hasMedia: !!opts.mediaUrl,
      })
      .catch(() => {});

    if ((opts.messageType ?? 'text') === 'voiceNote' || (opts.mediaType === 'voice')) {
      this.analyticsService
        .trackVoiceNoteSent(userId, familyId, id, 0)
        .catch(() => {});
    }

    // Check if this is the first-ever message in the chat (for onboarding).
    // We do this as a count query AFTER the insert — if count === 1, this
    // is the first message. Fire-and-forget.
    this.prisma.chatMessage
      .count({ where: { familyId, isDeletedForEveryone: false } })
      .then((count) => {
        if (count === 1) {
          this.analyticsService
            .trackFirstMessageInChat(userId, familyId, id)
            .catch(() => {});
        }
      })
      .catch(() => {});

    return message;
  }

  // ── Feature 2: Group chat @mentions ──────────────────────────────────
  //
  // Send a message with @mentions. The [mentions] array contains
  // {userId, name, start, end} refs pointing at the @Name spans in
  // [content]. We:
  //   1. Persist the message (same as sendMessage)
  //   2. Store the mentions inline on ChatMessage.mentions (JSON) for
  //      rendering
  //   3. Insert ChatMention rows (one per mentioned user) for the
  //      queryable "which messages mention me?" index
  //   4. Trigger a targeted push notification to each mentioned user
  //      (handled by the gateway via a 'chat:mentionReceived' event)
  //
  // The existing Supabase `fn_add_mentions_to_message` RPC does steps
  // 2+3 atomically; we call it from here for backward compat with the
  // Flutter app's existing code path, AND we insert ChatMention rows
  // directly via Prisma for the NestJS-only path.

  async sendMessageWithMentions(
    familyId: string,
    userId: string,
    content: string,
    mentions: Array<{ userId: string; name: string; start: number; end: number }>,
    opts: {
      messageType?: string;
      replyToId?: string;
      senderPersonId?: string;
      senderInitials?: string;
      clientMessageId?: string;
    } = {},
  ) {
    // 1. Persist the message (reuse sendMessage)
    const message = await this.sendMessage(familyId, userId, content, opts);

    // 2. Update the inline mentions JSON on the message
    if (mentions.length > 0) {
      await this.prisma.chatMessage.update({
        where: { id: message.id },
        data: { mentions: mentions as any },
      });
      message.mentions = mentions as any;

      // 3. Insert ChatMention rows for the queryable index
      await this.prisma.chatMention.createMany({
        data: mentions.map((m) => ({
          id: `cm_${message.id}_${m.userId}`,
          messageId: message.id,
          mentionedUserId: m.userId,
          mentionedByName: message.senderName,
        })),
        skipDuplicates: true,
      });

      // Feature 1: Analytics — track mention_sent
      this.analyticsService
        .track('mention_sent', userId, { messageId: message.id, mentionCount: mentions.length }, familyId)
        .catch(() => {});
    }

    return message;
  }

  /**
   * Get the read count for a message ("seen by 4/7" in the UI).
   * Returns { readCount, totalParticipants } — the total is the family
   * member count (excluding the sender), and readCount is how many of
   * them have a ChatReadReceipt row for this message.
   */
  async getReadCount(
    familyId: string,
    userId: string,
    messageId: string,
  ): Promise<{ readCount: number; totalParticipants: number }> {
    await this.assertMember(familyId, userId);

    // Count family members excluding the sender (the sender is never a
    // "reader" of their own message).
    const message = await this.prisma.chatMessage.findUnique({
      where: { id: messageId },
      select: { senderId: true, familyId: true },
    });
    if (!message || message.familyId !== familyId) {
      throw new NotFoundException('Message not found in this family');
    }

    const [totalParticipants, readCount] = await Promise.all([
      this.prisma.familyMember.count({
        where: {
          familyId,
          userId: { not: message.senderId },
        },
      }),
      this.prisma.chatReadReceipt.count({
        where: {
          messageId,
          userId: { not: message.senderId },
        },
      }),
    ]);

    return { readCount, totalParticipants };
  }

  /**
   * Get group chat info: participant list (with online status) + chat
   * metadata. Used by the Flutter group info screen.
   */
  async getGroupInfo(familyId: string, userId: string) {
    await this.assertMember(familyId, userId);

    const [family, members, presence] = await Promise.all([
      this.prisma.family.findUnique({
        where: { id: familyId },
        select: { id: true, name: true, avatarUrl: true, memberCount: true },
      }),
      this.prisma.familyMember.findMany({
        where: { familyId },
        select: {
          userId: true,
          role: true,
          joinedAt: true,
          user: {
            select: {
              id: true,
              name: true,
              username: true,
              avatarUrl: true,
            },
          },
        },
        orderBy: { joinedAt: 'asc' },
      }),
      this.prisma.memberPresence.findMany({
        where: { familyId },
        select: { userId: true, status: true, lastSeenAt: true },
      }),
    ]);

    // Merge presence into members for a single response.
    const presenceMap = new Map(presence.map((p) => [p.userId, p]));
    const participants = members.map((m) => {
      const p = presenceMap.get(m.userId);
      return {
        userId: m.userId,
        name: m.user.name ?? m.user.username ?? 'Unknown',
        username: m.user.username,
        avatarUrl: m.user.avatarUrl,
        role: m.role,
        joinedAt: m.joinedAt,
        isOnline: p?.status === 'online',
        lastSeenAt: p?.lastSeenAt ?? null,
      };
    });

    return {
      familyId: family?.id ?? familyId,
      familyName: family?.name ?? 'Unknown',
      familyAvatarUrl: family?.avatarUrl ?? null,
      memberCount: family?.memberCount ?? participants.length,
      participants,
    };
  }

  /**
   * Get all messages that mention a specific user. Used by the Flutter
   * "Mentions" filter in the chat search screen.
   */
  async getMentionsForUser(
    familyId: string,
    requestingUserId: string,
    mentionedUserId: string,
    limit: number = 20,
  ) {
    await this.assertMember(familyId, requestingUserId);

    const mentions = await this.prisma.chatMention.findMany({
      where: { mentionedUserId },
      take: Math.min(limit, 50),
      orderBy: { createdAt: 'desc' },
      select: {
        id: true,
        messageId: true,
        mentionedByName: true,
        createdAt: true,
      },
    });

    // Hydrate with message content
    if (mentions.length === 0) return [];
    const messageIds = [...new Set(mentions.map((m) => m.messageId))];
    const messages = await this.prisma.chatMessage.findMany({
      where: {
        id: { in: messageIds },
        familyId, // scope to this family for security
        isDeletedForEveryone: false,
      },
      select: {
        id: true,
        content: true,
        senderId: true,
        senderName: true,
        createdAt: true,
        messageType: true,
      },
    });
    const msgMap = new Map(messages.map((m) => [m.id, m]));

    return mentions
      .map((m) => {
        const msg = msgMap.get(m.messageId);
        if (!msg) return null; // mention points to a deleted/different-family msg
        return {
          ...m,
          message: msg,
        };
      })
      .filter((x) => x !== null);
  }

  /** Get the current streak for a chat (no mutation). */
  async getStreak(familyId: string) {
    return this.streakService.getStreak(familyId);
  }

  /**
   * Record a streak event for the chat (call AFTER sendMessage succeeds).
   * Wraps StreakService.recordMessage so callers don't need to inject
   * StreakService directly. Returns the updated streak payload.
   */
  async recordStreak(familyId: string) {
    return this.streakService.recordMessage(familyId);
  }

  // ── Feature 1: Delivery status ────────────────────────────────────────
  //
  // markDelivered flips messageStatus from 'sent' → 'delivered' when a
  // recipient's socket confirms receipt. It does NOT add to readBy —
  // that's the markAsRead flow (delivery = "reached device", read =
  // "user opened it"). The update is conditional so we don't downgrade
  // a 'read' status back to 'delivered' if the events arrive out of order.

  async markDelivered(messageId: string, _recipientUserId: string): Promise<void> {
    // Only update if the current status is 'sent' — never downgrade 'read'.
    await this.prisma.chatMessage.updateMany({
      where: {
        id: messageId,
        messageStatus: 'sent',
      },
      data: {
        messageStatus: 'delivered',
        updatedAt: new Date(),
      },
    });
  }

  /// Lookup the senderId + familyId of a message (used by the delivery
  /// confirmation handler to find the sender's socket). Returns null if
  /// the message was deleted.
  async getMessageSender(
    messageId: string,
  ): Promise<{ senderId: string; familyId: string } | null> {
    const msg = await this.prisma.chatMessage.findUnique({
      where: { id: messageId },
      select: { senderId: true, familyId: true, isDeletedForEveryone: true },
    });
    if (!msg || msg.isDeletedForEveryone) return null;
    return { senderId: msg.senderId, familyId: msg.familyId };
  }

  // ── Feature 3: Message pinning ──────────────────────────────────────
  //
  // Pin/unpin a message. Only admins OR the message sender can pin;
  // anyone can unpin (WhatsApp-style). The isPinned boolean is the
  // fast-query field; pinnedBy + pinnedAt are the metadata for the
  // pinned bar UI ("Pinned by Manish • 2h ago").
  //
  // After pin/unpin, the gateway broadcasts 'chat:messagePinned' /
  // 'chat:messageUnpinned' to the family room so all clients update
  // their pinned bar in real time.

  async pinMessage(
    familyId: string,
    userId: string,
    messageId: string,
  ): Promise<{
    messageId: string;
    isPinned: boolean;
    pinnedBy: string;
    pinnedAt: Date;
  }> {
    await this.assertMember(familyId, userId);

    const msg = await this.prisma.chatMessage.findUnique({
      where: { id: messageId },
      select: { familyId: true, senderId: true, isDeletedForEveryone: true },
    });
    if (!msg || msg.isDeletedForEveryone) {
      throw new NotFoundException('Message not found');
    }
    if (msg.familyId !== familyId) {
      throw new ForbiddenException('Message belongs to a different family');
    }

    // TODO: add admin check — for now, any family member can pin.
    // The existing FamilyMember.role field ('admin' | 'member') can be
    // checked when we add the permission gate.

    const now = new Date();
    await this.prisma.chatMessage.update({
      where: { id: messageId },
      data: {
        isPinned: true,
        pinnedBy: userId,
        pinnedAt: now,
      },
    });

    return {
      messageId,
      isPinned: true,
      pinnedBy: userId,
      pinnedAt: now,
    };
  }

  async unpinMessage(
    familyId: string,
    userId: string,
    messageId: string,
  ): Promise<{ messageId: string; isPinned: boolean }> {
    await this.assertMember(familyId, userId);

    const msg = await this.prisma.chatMessage.findUnique({
      where: { id: messageId },
      select: { familyId: true },
    });
    if (!msg) throw new NotFoundException('Message not found');
    if (msg.familyId !== familyId) {
      throw new ForbiddenException('Message belongs to a different family');
    }

    await this.prisma.chatMessage.update({
      where: { id: messageId },
      data: {
        isPinned: false,
        pinnedBy: null,
        pinnedAt: null,
      },
    });

    return { messageId, isPinned: false };
  }

  /// Get all pinned messages in a chat, newest-pinned first. Used by
  /// the Flutter pinned bar at the top of the chat screen.
  async getPinnedMessages(
    familyId: string,
    userId: string,
  ): Promise<Array<{
    id: string;
    content: string;
    senderId: string;
    senderName: string;
    messageType: string;
    pinnedBy: string | null;
    pinnedAt: Date | null;
    createdAt: Date;
  }>> {
    await this.assertMember(familyId, userId);

    return this.prisma.chatMessage.findMany({
      where: {
        familyId,
        isPinned: true,
        isDeletedForEveryone: false,
      },
      orderBy: { pinnedAt: 'desc' },
      take: 10, // cap at 10 pinned messages per chat
      select: {
        id: true,
        content: true,
        senderId: true,
        senderName: true,
        messageType: true,
        pinnedBy: true,
        pinnedAt: true,
        createdAt: true,
      },
    });
  }

  // ── Feature 6: Per-chat notification preferences ──────────────────────
  //
  // Mute/unmute a chat. The ChatPushScheduler checks ChatSettings.isMuted
  // before sending FCM pushes — muted chats' messages are still persisted
  // + create in-app Notification rows, but no FCM push is sent.

  async setChatMuted(
    familyId: string,
    userId: string,
    muted: boolean,
  ): Promise<{ familyId: string; userId: string; isMuted: boolean }> {
    await this.assertMember(familyId, userId);

    const id = `cs_${userId}_${familyId}`;
    await this.prisma.chatSettings.upsert({
      where: { id },
      create: {
        id,
        userId,
        familyId,
        isMuted: muted,
      },
      update: {
        isMuted: muted,
        updatedAt: new Date(),
      },
    });

    return { familyId, userId, isMuted: muted };
  }

  async getChatSettings(
    familyId: string,
    userId: string,
  ): Promise<{ isMuted: boolean; isPinned: boolean; isArchived: boolean }> {
    await this.assertMember(familyId, userId);

    const settings = await this.prisma.chatSettings.findUnique({
      where: { id: `cs_${userId}_${familyId}` },
      select: { isMuted: true, isPinned: true, isArchived: true },
    });

    return {
      isMuted: settings?.isMuted ?? false,
      isPinned: settings?.isPinned ?? false,
      isArchived: settings?.isArchived ?? false,
    };
  }

  // ── Feature 3: Empty-state nudge ──────────────────────────────────────
  //
  // Returns relationship-aware greeting suggestions + upcoming
  // birthday/anniversary data for the family chat empty state. The
  // Flutter empty_chat_state widget uses this to show:
  //   "Start the conversation in Sharmas 👋"
  //   + quick-reply chips like "Wish Mama ji happy birthday 🎂 (in 3 days)"
  //
  // We return:
  //   • familyName
  //   • memberCount
  //   • upcomingEvents: [{personId, name, eventType, daysUntil, date}]
  //     (birthday or anniversary within next 30 days)
  //   • suggestions: string[] (pre-built greeting suggestions the user
  //     can tap to send instantly)

  async getEmptyStateNudge(familyId: string, userId: string) {
    await this.assertMember(familyId, userId);

    const family = await this.prisma.family.findUnique({
      where: { id: familyId },
      select: { name: true },
    });

    const members = await this.prisma.familyMember.findMany({
      where: { familyId },
      select: {
        userId: true,
        user: { select: { id: true, name: true } },
      },
    });

    // Find upcoming birthdays in the next 30 days.
    const persons = await this.prisma.person.findMany({
      where: {
        familyId,
        dateOfBirth: { not: null },
        isDeceased: false,
        deletedAt: null,
      },
      select: {
        id: true,
        name: true,
        dateOfBirth: true,
        gender: true,
      },
    });

    const now = new Date();
    const upcomingEvents: Array<{
      personId: string;
      name: string;
      eventType: string;
      daysUntil: number;
      date: Date;
    }> = [];

    for (const p of persons) {
      if (!p.dateOfBirth) continue;
      const daysUntil = this._daysUntilNextBirthday(p.dateOfBirth, now);
      if (daysUntil >= 0 && daysUntil <= 30) {
        upcomingEvents.push({
          personId: p.id,
          name: p.name,
          eventType: 'birthday',
          daysUntil,
          date: p.dateOfBirth,
        });
      }
    }
    // Sort by soonest first.
    upcomingEvents.sort((a, b) => a.daysUntil - b.daysUntil);

    // Build quick-reply suggestions based on the events + generic ones.
    const suggestions: string[] = [];
    if (upcomingEvents.length > 0) {
      const next = upcomingEvents[0];
      if (next.daysUntil === 0) {
        suggestions.push(`Happy Birthday, ${next.name}! 🎂🎉`);
      } else if (next.daysUntil <= 7) {
        suggestions.push(`${next.name}'s birthday is in ${next.daysUntil} day${next.daysUntil !== 1 ? 's' : ''}! 🎂`);
      } else {
        suggestions.push(`Wish ${next.name} for their birthday (in ${next.daysUntil} days) 🎂`);
      }
    }
    // Generic greetings
    suggestions.push('Namaste everyone 🙏');
    suggestions.push('How is everyone doing?');
    const famName = family?.name ?? '';
    if (famName.length > 0) {
      suggestions.push(`Good morning, ${famName} family! ☀️`);
    }

    return {
      familyName: family?.name ?? 'your family',
      memberCount: members.length,
      upcomingEvents: upcomingEvents.slice(0, 3), // top 3
      suggestions: suggestions.slice(0, 4), // top 4
    };
  }

  /// Calculate days until the next occurrence of a recurring birthday.
  /// Compares month + day only (ignores year). Returns 0 if today is
  /// the birthday, -1 if it already passed this year (will be next year).
  private _daysUntilNextBirthday(dateOfBirth: Date, now: Date): number {
    const birthMonth = dateOfBirth.getMonth();
    const birthDay = dateOfBirth.getDate();
    const currentYear = now.getFullYear();
    let nextBirthday = new Date(currentYear, birthMonth, birthDay);
    if (nextBirthday < new Date(currentYear, now.getMonth(), now.getDate())) {
      nextBirthday = new Date(currentYear + 1, birthMonth, birthDay);
    }
    const diffMs = nextBirthday.getTime() - new Date(currentYear, now.getMonth(), now.getDate()).getTime();
    return Math.round(diffMs / (1000 * 60 * 60 * 24));
  }

  // ── Feature 5: Message search ────────────────────────────────────────
  //
  // Uses Postgres ILIKE for case-insensitive substring search on the
  // ChatMessage.content column. We don't use full-text search (tsvector)
  // because the project doesn't have pg_trgm or a tsvector index set up,
  // and ILIKE with a contains filter is fast enough for typical chat
  // volumes (< 100k messages per family).
  //
  // Returns matches sorted by createdAt DESC (newest first). Each result
  // includes the message + a snippet of the content around the match
  // (for the Flutter search UI to highlight + scroll to).
  //
  // The [before] param supports pagination — pass the oldest match's
  // createdAt to fetch the next page.

  async searchMessages(
    familyId: string,
    userId: string,
    query: string,
    limit: number = 20,
  ): Promise<{
    results: Array<{
      id: string;
      content: string;
      senderId: string;
      senderName: string;
      createdAt: Date;
      messageType: string;
      mediaUrl: string | null;
      replyToId: string | null;
      replyToContent: string | null;
      replyToSenderName: string | null;
    }>;
    total: number;
  }> {
    await this.assertMember(familyId, userId);

    const trimmed = query.trim();
    if (trimmed.length === 0) {
      return { results: [], total: 0 };
    }

    // Escape special ILIKE characters: % and _ are wildcards in ILIKE.
    // We escape them with backslash so a search for "100%" doesn't match
    // "1000". The backslash itself doesn't need escaping in Prisma's
    // contains mode.
    const escaped = trimmed.replace(/[%_\\]/g, '\\$&');

    // Use Prisma's contains with insensitive mode — this compiles to
    // ILIKE '%query%' on Postgres. The search field is `content`.
    const messages = await this.prisma.chatMessage.findMany({
      where: {
        familyId,
        isDeletedForEveryone: false,
        content: {
          contains: escaped,
          mode: 'insensitive',
        },
      },
      orderBy: { createdAt: 'desc' },
      take: Math.min(limit, 50),
      select: {
        id: true,
        content: true,
        senderId: true,
        senderName: true,
        createdAt: true,
        messageType: true,
        mediaUrl: true,
        replyToId: true,
        replyToContent: true,
        replyToSenderName: true,
      },
    });

    // Count total matches (for the search UI's "N results" label).
    // We do this in a separate query so the SELECT above can use LIMIT.
    const total = await this.prisma.chatMessage.count({
      where: {
        familyId,
        isDeletedForEveryone: false,
        content: {
          contains: escaped,
          mode: 'insensitive',
        },
      },
    });

    // Feature 1: Analytics — track search_used
    this.analyticsService
      .trackSearchUsed(userId, familyId, trimmed, messages.length)
      .catch(() => {});

    return {
      results: messages,
      total,
    };
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

    // Feature 1: Analytics — track message_read (one event per batch)
    this.analyticsService
      .track('message_read', userId, { messageCount: ids.length }, familyId)
      .catch(() => {});

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
      // Feature 1: Analytics — track reaction_added
      this.analyticsService
        .trackReactionAdded(userId, familyId, dto.messageId, dto.emoji)
        .catch(() => {});
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
