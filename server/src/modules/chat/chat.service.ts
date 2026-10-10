import {
  Injectable,
  ForbiddenException,
  NotFoundException,
  BadRequestException,
  Logger,
} from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';
import { StreakService } from './streak.service';
import { ChatAnalyticsService } from '../analytics/chat-analytics.service';
import { PrivacyService } from './privacy.service';
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
    // Tier 3 Feature 3.5: PrivacyService gates lastSeenAt visibility in
    // getGroupInfo based on the OTHER user's lastSeenVisibility setting.
    // We use forwardRef because PrivacyService is in the same module.
    private readonly privacyService: PrivacyService,
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

  /**
   * Tier 2 Feature 2.6: public role lookup. Returns the user's role in
   * the family ('member' | 'admin' | 'creator') or null if not a member.
   * Used by ChatGateway to decide whether slow-mode should apply (admins
   * bypass slow-mode).
   */
  async getMembershipRole(familyId: string, userId: string): Promise<string | null> {
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId, userId } },
      select: { role: true },
    });
    return membership?.role ?? null;
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
      /// Tier 1 Feature 1.4: silent send. When true, FCM push for this
      /// message is delivered at low priority with no sound + no
      /// vibration. Default false.
      silent?: boolean;
      /// Tier 1 Feature 1.14: caption for media messages. Renders below
      /// the photo/video inside the bubble. Null for non-media types.
      caption?: string;
      /// Tier 1 Feature 1.5: view-once media. When true, the recipient
      /// sees a special bubble + the underlying media is deleted 24h
      /// after the first view.
      isViewOnce?: boolean;
      /// Tier 1 Feature 1.6: photo quality tier — 'standard' (1600px)
      /// or 'hd' (original resolution). Default 'standard'.
      qualityTier?: string;
      /// Tier 1 Feature 1.11: document display name (for PDF/DOCX/etc.).
      documentName?: string;
      /// Tier 1 Feature 1.11: document page count (for PDFs).
      documentPages?: number;
      /// Tier 2 Feature 2.7: anonymous admin — only admins/creators can use.
      isAnonymousAdmin?: boolean;
      /// Tier 2 Feature 2.5: forum topic — null = General.
      topicId?: string;
      /// Tier 6 Feature 6.5: message effect — 'gentle' | 'loud' |
      /// 'invisibleInk' | 'confetti' | 'fireworks' | 'balloons'. Null = none.
      effectType?: string;
    } = {},
  ) {
    const membership = await this.assertMember(familyId, userId);
    const { displayName, initials } = await this.resolveSender(userId);

    // ── Tier 2 Feature 2.7: Anonymous admin messages ────────────────
    // Only admins/creators can send anonymous-admin messages. If a non-
    // admin passes isAnonymousAdmin=true, we silently downgrade to
    // false (rather than throwing — matches WhatsApp's "no error, just
    // ignore the flag" UX for unsupported client behavior).
    let isAnonymousAdmin = opts.isAnonymousAdmin ?? false;
    if (isAnonymousAdmin && membership.role !== 'admin' && membership.role !== 'creator') {
      isAnonymousAdmin = false;
    }

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
        // Tier 2 Feature 2.7: when isAnonymousAdmin=true, the sender's
        // DISPLAY name is overwritten with 'Admin' so the bubble shows
        // "Admin" instead of the admin's real name. The senderId stays
        // the user's id so audit + ownership checks still work.
        senderName: isAnonymousAdmin ? 'Admin' : displayName,
        senderInitials: isAnonymousAdmin ? 'A' : (opts.senderInitials ?? initials),
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
        // Tier 1 features: silent + caption + view-once + HD + document.
        silent: opts.silent ?? false,
        caption: opts.caption ?? null,
        isViewOnce: opts.isViewOnce ?? false,
        qualityTier: opts.qualityTier ?? 'standard',
        documentName: opts.documentName ?? null,
        documentPages: opts.documentPages ?? null,
        // Tier 2 Feature 2.7: anonymous admin flag.
        isAnonymousAdmin,
        // Tier 2 Feature 2.5: forum topics — null = General topic.
        topicId: opts.topicId ?? null,
        // Tier 6 Feature 6.5: message effects (null = no effect).
        effectType: opts.effectType ?? null,
      },
      include: { reactions: true },
    });

    // ── Tier 2 Feature 2.8: Admin audit log for anonymous messages ──
    // Fire-and-forget — failures here don't break the send.
    if (isAnonymousAdmin) {
      this.prisma.$queryRaw`SELECT fn_log_group_audit(${familyId}, ${userId}, 'anonymous_admin_message_sent', NULL, ${id}, '[]'::jsonb)`.catch(() => {});
    }

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
    // Tier 3 Feature 3.5: gate lastSeenAt visibility based on the
    // participant's privacy setting + reciprocity (requester's own
    // setting also applies — if they hide from everyone, they can't
    // see anyone's last-seen either).
    const presenceMap = new Map(presence.map((p) => [p.userId, p]));
    const participants = await Promise.all(
      members.map(async (m) => {
        const p = presenceMap.get(m.userId);
        // Gate lastSeenAt — the privacy check returns false for users
        // who set lastSeenVisibility='nobody' or when the requester has
        // lastSeenVisibility='nobody' themselves.
        const canSeeLastSeen = await this.privacyService.canSeeLastSeenOf(userId, m.userId);
        return {
          userId: m.userId,
          name: m.user.name ?? m.user.username ?? 'Unknown',
          username: m.user.username,
          avatarUrl: m.user.avatarUrl,
          role: m.role,
          joinedAt: m.joinedAt,
          isOnline: p?.status === 'online',
          // Hide the timestamp when the requester can't see it. isOnline
          // stays visible (privacy is about the TIMESTAMP, not the online
          // status — matches WhatsApp's "online" label vs. "last seen X ago").
          lastSeenAt: canSeeLastSeen ? (p?.lastSeenAt ?? null) : null,
        };
      }),
    );

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

  // ── Tier 4 Features 4.2 + 4.3: Edit message (text + media swap + history) ──
  //
  // Lets a sender edit their own message. Captures the previous (content,
  // mediaUrl, caption) into editHistory BEFORE the update so the array
  // grows monotonically. Sets isEdited=true + editedAt=now().
  //
  // Only the original sender can edit. Deleted-for-everyone messages
  // can't be edited (matches WhatsApp — once you "delete for everyone"
  // a message, you can't bring it back via the edit path).
  //
  // Returns the updated message so the gateway can broadcast it.
  async editMessage(
    familyId: string,
    userId: string,
    messageId: string,
    params: {
      newContent?: string | null;
      newMediaUrl?: string | null;
      newCaption?: string | null;
    },
  ) {
    await this.assertMember(familyId, userId);

    const existing = await this.prisma.chatMessage.findUnique({
      where: { id: messageId },
      select: {
        senderId: true,
        familyId: true,
        content: true,
        mediaUrl: true,
        caption: true,
        isDeletedForEveryone: true,
        editHistory: true,
      },
    });
    if (!existing) {
      throw new NotFoundException('Message not found');
    }
    if (existing.familyId !== familyId) {
      throw new ForbiddenException('Message belongs to a different family');
    }
    if (existing.senderId !== userId) {
      throw new ForbiddenException('Only the sender can edit their message');
    }
    if (existing.isDeletedForEveryone) {
      throw new BadRequestException('Cannot edit a deleted message');
    }

    // Build the previous-state snapshot (stored in editHistory).
    // Note: editHistory grows monotonically — each edit appends one entry.
    const now = new Date();
    const oldSnapshot: any = {
      content: existing.content,
      mediaUrl: existing.mediaUrl,
      caption: existing.caption,
      editedAt: now.toISOString(),
    };
    const newHistory = [
      ...((existing.editHistory as any[]) ?? []),
      oldSnapshot,
    ];

    // Compute the new field values — null params mean "leave unchanged".
    const data: any = {
      isEdited: true,
      editedAt: now,
      editHistory: newHistory,
      updatedAt: now,
    };
    if (params.newContent !== null && params.newContent !== undefined) {
      data.content = params.newContent;
    }
    if (params.newMediaUrl !== null && params.newMediaUrl !== undefined) {
      data.mediaUrl = params.newMediaUrl;
    }
    if (params.newCaption !== null && params.newCaption !== undefined) {
      // Empty string clears the caption (matches WhatsApp behavior).
      data.caption = params.newCaption === '' ? null : params.newCaption;
    }

    return this.prisma.chatMessage.update({
      where: { id: messageId },
      data,
      include: { reactions: true },
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
        // Tier 3 Feature 3.4: when unmuting, clear mutedUntil; when muting
        // without a duration, leave mutedUntil null (= no expiry).
        mutedUntil: muted ? null : null,
      },
      update: {
        isMuted: muted,
        mutedUntil: null,
        updatedAt: new Date(),
      },
    });

    return { familyId, userId, isMuted: muted };
  }

  // ── Tier 3 Feature 3.4: Mute with custom duration ────────────────────
  // Mutes the chat until a specific future timestamp (e.g. now + 8h).
  // Pass null to unmute immediately. The ChatPushScheduler checks
  // (isMuted OR (mutedUntil > now())) to decide whether to suppress the push.
  async setChatMutedUntil(
    familyId: string,
    userId: string,
    mutedUntil: Date | null,
  ): Promise<{ familyId: string; userId: string; isMuted: boolean; mutedUntil: Date | null }> {
    await this.assertMember(familyId, userId);

    // Effective mute: mutedUntil must be in the future.
    const now = new Date();
    const effectiveMuted = mutedUntil !== null && mutedUntil > now;

    const id = `cs_${userId}_${familyId}`;
    await this.prisma.chatSettings.upsert({
      where: { id },
      create: {
        id,
        userId,
        familyId,
        isMuted: effectiveMuted,
        mutedUntil,
      },
      update: {
        isMuted: effectiveMuted,
        mutedUntil,
        updatedAt: now,
      },
    });

    return { familyId, userId, isMuted: effectiveMuted, mutedUntil };
  }

  // ── Tier 3 Feature 3.2: Pin chats ────────────────────────────────────
  // Pin a chat at a given order, or unpin (when pinnedOrder is null).
  // Caps at 5 pinned per user (matches WhatsApp).
  async setChatPinned(
    familyId: string,
    userId: string,
    pinnedOrder: number | null,
  ): Promise<{ familyId: string; userId: string; pinnedOrder: number | null }> {
    await this.assertMember(familyId, userId);

    if (pinnedOrder !== null) {
      // Enforce max 5 pinned per user.
      const count = await this.prisma.chatSettings.count({
        where: { userId, pinnedOrder: { not: null } },
      });
      // Allow the caller to RE-pin a chat they've already pinned (count
      // stays the same), but block NEW pins beyond 5.
      const existing = await this.prisma.chatSettings.findUnique({
        where: { id: `cs_${userId}_${familyId}` },
        select: { pinnedOrder: true },
      });
      const isAlreadyPinned = existing?.pinnedOrder !== null && existing?.pinnedOrder !== undefined;
      if (count >= 5 && !isAlreadyPinned) {
        throw new BadRequestException('You can pin at most 5 chats.');
      }
    }

    const id = `cs_${userId}_${familyId}`;
    await this.prisma.chatSettings.upsert({
      where: { id },
      create: {
        id,
        userId,
        familyId,
        pinnedOrder,
      },
      update: {
        pinnedOrder,
        updatedAt: new Date(),
      },
    });

    return { familyId, userId, pinnedOrder };
  }

  // ── Tier 3 Feature 3.3: Mark as unread (toggle) ─────────────────────
  async setChatForcedUnread(
    familyId: string,
    userId: string,
    forcedUnread: boolean,
  ): Promise<{ familyId: string; userId: string; forcedUnread: boolean }> {
    await this.assertMember(familyId, userId);

    const id = `cs_${userId}_${familyId}`;
    await this.prisma.chatSettings.upsert({
      where: { id },
      create: {
        id,
        userId,
        familyId,
        forcedUnread,
      },
      update: {
        forcedUnread,
        updatedAt: new Date(),
      },
    });

    return { familyId, userId, forcedUnread };
  }

  async getChatSettings(
    familyId: string,
    userId: string,
  ): Promise<{
    isMuted: boolean;
    isPinned: boolean;
    isArchived: boolean;
    pinnedOrder: number | null;
    forcedUnread: boolean;
    mutedUntil: Date | null;
  }> {
    await this.assertMember(familyId, userId);

    const settings = await this.prisma.chatSettings.findUnique({
      where: { id: `cs_${userId}_${familyId}` },
      select: {
        isMuted: true,
        isPinned: true,
        isArchived: true,
        pinnedOrder: true,
        forcedUnread: true,
        mutedUntil: true,
      },
    });

    return {
      isMuted: settings?.isMuted ?? false,
      isPinned: settings?.isPinned ?? false,
      isArchived: settings?.isArchived ?? false,
      pinnedOrder: settings?.pinnedOrder ?? null,
      forcedUnread: settings?.forcedUnread ?? false,
      mutedUntil: settings?.mutedUntil ?? null,
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
    filters?: {
      mediaType?: string;       // Tier 3 Feature 3.8: filter by message media type
      senderId?: string;       // Tier 3 Feature 3.8: filter by sender
      fromDate?: Date;         // Tier 3 Feature 3.8: filter by date range
      toDate?: Date;
    },
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

    // ── Tier 3 Feature 3.8: when filters are present (mediaType, senderId,
    // date range), we allow an empty query — the user is browsing all
    // photos from Mama ji in March, not searching for a specific string.
    const hasFilters = !!(
      filters?.mediaType ||
      filters?.senderId ||
      filters?.fromDate ||
      filters?.toDate
    );

    if (trimmed.length === 0 && !hasFilters) {
      return { results: [], total: 0 };
    }

    // Escape special ILIKE characters: % and _ are wildcards in ILIKE.
    // We escape them with backslash so a search for "100%" doesn't match
    // "1000". The backslash itself doesn't need escaping in Prisma's
    // contains mode.
    const escaped = trimmed.replace(/[%_\\]/g, '\\$&');

    // Build the where clause with the Tier 3 filters applied.
    const where: any = {
      familyId,
      isDeletedForEveryone: false,
    };
    if (trimmed.length > 0) {
      where.content = { contains: escaped, mode: 'insensitive' };
    }
    if (filters?.mediaType) {
      // mediaType filter — maps "photos" → messageType='photo', etc.
      // The Flutter filter chip sends a human-readable category; we
      // translate to the canonical messageType value here.
      const mt = filters.mediaType.toLowerCase();
      if (mt === 'photos' || mt === 'photo' || mt === 'image') {
        where.messageType = 'photo';
      } else if (mt === 'videos' || mt === 'video') {
        where.messageType = 'video';
      } else if (mt === 'voice' || mt === 'audio') {
        where.messageType = 'voiceNote';
      } else if (mt === 'documents' || mt === 'document' || mt === 'docs') {
        where.messageType = 'document';
      } else if (mt === 'links' || mt === 'link') {
        // No 'link' messageType — search for messages containing "http"
        // as a best-effort proxy.
        where.content = { contains: 'http', mode: 'insensitive' };
      } else {
        // Pass-through for callers that already know the canonical type.
        where.messageType = mt;
      }
    }
    if (filters?.senderId) {
      where.senderId = filters.senderId;
    }
    if (filters?.fromDate || filters?.toDate) {
      const createdAtFilter: any = {};
      if (filters.fromDate) createdAtFilter.gte = filters.fromDate;
      if (filters.toDate) createdAtFilter.lte = filters.toDate;
      where.createdAt = createdAtFilter;
    }

    // Use Prisma's contains with insensitive mode — this compiles to
    // ILIKE '%query%' on Postgres. The search field is `content`.
    const messages = await this.prisma.chatMessage.findMany({
      where,
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
    const total = await this.prisma.chatMessage.count({ where });

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

    // ── Tier 3 Feature 3.5: Read receipts privacy suppression ───────
    // When the READER has readReceiptsEnabled=false, suppress the
    // readBy writes (the sender can't see they read it). Symmetric:
    // when the SENDER has readReceiptsEnabled=false, the reader's
    // read state is also suppressed on their messages (matches
    // WhatsApp — both directions are gated). We check the reader's
    // flag here; per-sender flag is checked in the loop below.
    const readerHasReceiptsEnabled = await this.privacyService.hasReadReceiptsEnabled(userId);
    if (!readerHasReceiptsEnabled) {
      // The reader disabled read receipts — silently no-op (the
      // messages are still considered "read" by the client's local
      // state, but the server doesn't persist a readBy entry).
      this.logger.debug(
        `markAsRead suppressed for ${userId} (readReceiptsEnabled=false)`,
      );
      return { markedReadIds: [], senderIds: [] };
    }

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

    // ── Tier 3 Feature 3.5: per-sender suppression ─────────────────
    // Filter out messages whose SENDER has readReceiptsEnabled=false
    // (the sender opted out, so the reader's read state isn't shared
    // back to them).
    const senderFlags = new Map<string, boolean>();
    const uniqueSenderIds = [...new Set(unread.map((m) => m.senderId))];
    await Promise.all(
      uniqueSenderIds.map(async (sid) => {
        senderFlags.set(sid, await this.privacyService.hasReadReceiptsEnabled(sid));
      }),
    );
    const allowedUnread = unread.filter((m) => senderFlags.get(m.senderId) !== false);
    if (allowedUnread.length === 0) {
      // Every unread message's sender disabled read receipts — no-op.
      return { markedReadIds: [], senderIds: [] };
    }

    const now = new Date();
    const ids = allowedUnread.map((m) => m.id);

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
    const senderIds = [...new Set(allowedUnread.map((m) => m.senderId))];

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
