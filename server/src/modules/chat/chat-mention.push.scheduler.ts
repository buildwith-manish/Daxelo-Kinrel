// server/src/modules/chat/chat-mention.push.scheduler.ts
//
// Phase A — @mentions across chat.
//
// Smart batched push notifications for chat mentions. Distinct from
// ChatPushScheduler (which batches regular unread messages) because
// mentions carry different semantics:
//
//   • Cap-at-most-once: each ChatMention row is pushed at most once
//     (the `notifiedAt` column flips when the push fires).
//   • Per-recipient batching window: when a user gets multiple mentions
//     in a short window (e.g. two people @-mention them in different
//     chats within 5-10s), they get ONE batched FCM push instead of N.
//   • Skip-if-online: if the recipient is currently viewing the chat
//     the mention came from (their socket is joined to the chat room),
//     the push is skipped — they're already reading it.
//   • Mute-aware: respects ChatSettings.isMuted UNLESS the recipient
//     has NotificationPreference.mentionsBreakMute=true (default true).
//     Judged PER MENTION at enqueue time (by the mention's own chat), so a
//     batch only ever holds mentions that may push — a muted chat's mention
//     is dropped without suppressing a mention from an unmuted chat.
//     Granularity is per (user, family): ChatSettings has no per-group mute.
//   • Quiet-hours-aware: respects NotificationPreference.quietHoursStart/End,
//     read in the recipient's own quietHoursTimezone (not the server clock).
//   • Block-aware: never push if the recipient has blocked the sender
//     (BlockedUser row exists with blockerId=recipient, blockedId=sender).
//     The sender is resolved from ChatMessage.senderId via the mention's
//     messageId (ChatMention only stores a display-name snapshot).
//   • Cron retry: a 30s cron picks up any mention rows whose push failed
//     (FCM token invalid, network blip) and retries once. After the
//     retry, the row is marked notified regardless of outcome so a
//     bad token doesn't infinite-loop the scheduler.
//
// Body text (per the user's revised plan):
//   "{senderDisplayName} mentioned you in {chatDisplayName}"
//   • Plain names — no server-side kinship lookup. The Flutter in-app
//     banner enriches with the recipient's kinship term for the sender
//     (resolved via kinshipTermsForFamilyProvider on the client).
//   • chatDisplayName = family name for family-wide messages, group
//     name for group messages, sender name + " · DM" for direct
//     messages (though DMs never have notify=true mentions — see
//     ChatService.sendMessageWithMentions).
//
// Why a separate scheduler (vs extending ChatPushScheduler):
//   • Different row source (ChatMention vs ChatMessage).
//   • Different push body + analytics event.
//   • Different mute semantics (mentionsBreakMute setting only applies
//     to mentions; regular messages always respect mute).
//   • Different batching key (per-recipient, not per-(recipient, family)).

import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { PrismaService } from '../../prisma/prisma.service';
import { FcmService } from '../notifications/fcm.service';
import { KinrelGateway } from '../gateway/kinrel.gateway';
import { isInQuietHoursInTz } from '../notifications/timezone-utils';

@Injectable()
export class ChatMentionPushScheduler {
  private readonly logger = new Logger(ChatMentionPushScheduler.name);

  /// Per-recipient batching window. The spec says 5-10s; we pick 7s
  /// as a midpoint — long enough that bursts coalesce, short enough
  /// that a single mention doesn't feel sluggish.
  private readonly batchWindowMs = 7_000;

  /// In-flight batch timers, keyed by recipient userId. When the first
  /// mention for a recipient arrives, a timer is set; subsequent
  /// mentions for the same recipient reset the timer (debounce-style).
  /// When the timer fires, all queued mentions for that recipient are
  /// pushed in a single FCM message.
  private readonly pendingBatches = new Map<
    string,
    { mentions: PendingMention[]; timer: NodeJS.Timeout }
  >();

  constructor(
    private readonly prisma: PrismaService,
    private readonly fcmService: FcmService,
    private readonly kinrelGateway: KinrelGateway,
  ) {}

  /// Called by ChatService (or the gateway) when a new mention is
  /// persisted. Enqueues the mention for batched push.
  async enqueueMention(mentionId: string): Promise<void> {
    try {
      const mention = await this.prisma.chatMention.findUnique({
        where: { id: mentionId },
      });
      if (!mention) {
        this.logger.warn(`enqueueMention: mention ${mentionId} not found`);
        return;
      }
      if (!mention.notify) {
        // DM reference — never pushes. The ChatService should have
        // already filtered this out, but defensive.
        return;
      }

      // Skip-if-online: check the recipient's presence via the
      // gateway's connectedUsers map. If they have ANY active socket we
      // skip the push entirely (v1 behaviour). We cannot tell which chat
      // they are looking at: a socket joins several chat:family:* /
      // chat:group:* rooms just by being connected, and the Flutter app
      // never reports which chat is on screen.
      // TODO(phase-a-5, BLOCKED on Flutter): precise "already viewing THIS
      // chat" needs the client to emit a viewing-state event (e.g.
      // `chat:viewing { familyId, groupId|null }` on open, a clear on
      // close/background) and the server to keep it per socket. Not built
      // here on purpose — without the client signal the check would never
      // fire, and swapping the any-socket skip for it would START pushing
      // to users who are online. Until then this stays any-socket.
      const isOnline = this.kinrelGateway.isUserConnected(mention.mentionedUserId);
      if (isOnline) {
        // Mark as notified so the cron retry doesn't re-fire. The
        // in-app `chat:mentionReceived` socket event (fired by the
        // gateway at send time) already told the client about it.
        await this.prisma.chatMention.update({
          where: { id: mention.id },
          data: { notifiedAt: new Date() },
        });
        return;
      }

      // Quiet hours, block list and mute are all evaluated for THIS
      // mention (its own message / chat) before it can join the batch.
      const recipientId = mention.mentionedUserId;
      const shouldPush = await this.shouldPushForRecipient(
        recipientId,
        mention.messageId,
      );
      if (!shouldPush) {
        await this.prisma.chatMention.update({
          where: { id: mention.id },
          data: { notifiedAt: new Date() },
        });
        return;
      }

      // Enqueue in the per-recipient batch.
      const existing = this.pendingBatches.get(recipientId);
      const pending: PendingMention = {
        mentionId: mention.id,
        messageId: mention.messageId,
        senderName: mention.mentionedByName,
        groupId: mention.groupId,
      };
      if (existing) {
        existing.mentions.push(pending);
        // Reset the timer (debounce).
        clearTimeout(existing.timer);
        existing.timer = setTimeout(
          () => this.flushBatch(recipientId),
          this.batchWindowMs,
        );
      } else {
        const timer = setTimeout(
          () => this.flushBatch(recipientId),
          this.batchWindowMs,
        );
        this.pendingBatches.set(recipientId, {
          mentions: [pending],
          timer,
        });
      }
    } catch (err: any) {
      this.logger.error(
        `enqueueMention failed for ${mentionId}: ${err?.message}`,
        err?.stack,
      );
    }
  }

  /// Flush a recipient's pending batch as a single FCM push.
  private async flushBatch(recipientId: string): Promise<void> {
    const batch = this.pendingBatches.get(recipientId);
    this.pendingBatches.delete(recipientId);
    if (!batch || batch.mentions.length === 0) return;

    try {
      const first = batch.mentions[0];
      const count = batch.mentions.length;
      const body =
        count === 1
          ? `${first.senderName} mentioned you in chat`
          : `${first.senderName} and ${count - 1} other${
              count - 1 === 1 ? '' : 's'
            } mentioned you in chat`;

      const fcmDelivered = await this.fcmService.sendToUser(recipientId, {
        title: 'New mention',
        body,
        data: {
          type: 'chat_mention',
          // Deep-link to the chat thread when the user taps the push.
          messageId: first.messageId,
          groupId: first.groupId ?? '',
        },
      });

      // Mark all the mentions in the batch as notified regardless of
      // FCM outcome — a bad token shouldn't infinite-loop the
      // scheduler. The cron retry only fires for rows whose notifiedAt
      // is still NULL after a config'd grace period (see handleRetry).
      const now = new Date();
      await this.prisma.chatMention.updateMany({
        where: { id: { in: batch.mentions.map((m) => m.mentionId) } },
        data: { notifiedAt: now },
      });

      if (!fcmDelivered) {
        this.logger.warn(
          `FCM push to ${recipientId} for ${count} mention(s) didn't deliver (token missing, Firebase not initialized, or send failed)`,
        );
      }
    } catch (err: any) {
      this.logger.error(
        `flushBatch failed for ${recipientId}: ${err?.message}`,
        err?.stack,
      );
    }
  }

  /// Decide whether a push should fire for ONE mention (identified by its
  /// messageId) to this recipient. Checks, in order: quiet hours, block
  /// list, mute (with the mentionsBreakMute override). Because it runs per
  /// mention, the per-recipient batch only ever contains mentions that are
  /// allowed to push — there is no batch-wide "all muted?" guess. All
  /// failures, and a mention whose message cannot be found, default to
  /// "don't push" (fail-closed for privacy).
  private async shouldPushForRecipient(
    recipientId: string,
    messageId: string,
  ): Promise<boolean> {
    try {
      // 1. NotificationPreference (quiet hours + mentionsBreakMute).
      // NotificationPreference's primary key is `id` (cuid), not
      // userId — multiple rows per user exist (one per eventType). Use
      // findFirst to grab any matching row; the mentionsBreakMute +
      // quietHours fields are user-global per the spec.
      const pref = await this.prisma.notificationPreference.findFirst({
        where: { userId: recipientId },
      });
      // Quiet hours — always respected regardless of mentionsBreakMute.
      if (pref && this.isInQuietHours(pref)) {
        return false;
      }

      // 2. The mention's message: gives us the chat (familyId) for the
      // mute check and the sender (senderId) for the block check.
      const msg = await this.prisma.chatMessage.findUnique({
        where: { id: messageId },
        select: { familyId: true, senderId: true },
      });
      if (!msg) {
        this.logger.warn(
          `shouldPushForRecipient: message ${messageId} not found; not pushing`,
        );
        return false;
      }

      // 3. Block list — always respected. The recipient is the blocker.
      const blocked = await this.prisma.blockedUser.findFirst({
        where: { blockerId: recipientId, blockedId: msg.senderId },
        select: { id: true },
      });
      if (blocked) {
        return false;
      }

      // 4. Mute. mentionsBreakMute defaults to TRUE (no pref row = true):
      // a mention then pushes even from a muted chat. Only when the
      // recipient opted OUT of that do we honour ChatSettings.isMuted, and
      // only for THIS mention's chat. ChatSettings is keyed by
      // (userId, familyId) — there is no per-group mute column, so a
      // group/DM mention follows its family's mute state.
      const breakMute = pref?.mentionsBreakMute ?? true;
      if (!breakMute) {
        const muted = await this.prisma.chatSettings.findFirst({
          where: { userId: recipientId, familyId: msg.familyId, isMuted: true },
          select: { id: true },
        });
        if (muted) {
          return false;
        }
      }
      return true;
    } catch (err: any) {
      this.logger.error(
        `shouldPushForRecipient failed for ${recipientId}: ${err?.message}`,
        err?.stack,
      );
      // Fail-closed: don't push on uncertain state.
      return false;
    }
  }

  /// Check whether the recipient is currently inside their quiet-hours
  /// window. The window ("HH:MM" start/end) is wall-clock time in the
  /// recipient's own `quietHoursTimezone` (default 'Asia/Kolkata'), NOT the
  /// server's clock. Quiet hours are considered configured when BOTH start
  /// and end are set — `NotificationPreference` has no separate enabled
  /// flag, and the other schedulers use the same rule.
  private isInQuietHours(
    pref: {
      quietHoursStart?: string | null;
      quietHoursEnd?: string | null;
      quietHoursTimezone?: string | null;
    },
    now: Date = new Date(),
  ): boolean {
    return isInQuietHoursInTz(
      now,
      pref.quietHoursStart,
      pref.quietHoursEnd,
      pref.quietHoursTimezone,
    );
  }

  /// Cron retry: every 30s, find ChatMention rows whose notify=true
  /// and notifiedAt IS NULL and are older than the batch window + a
  /// 10s grace. These are mentions that the per-event path failed to
  /// push (e.g. the gateway was mid-restart when the mention was
  /// created). Fire-and-forget push; mark notifiedAt regardless of
  /// outcome so a bad FCM token doesn't infinite-loop.
  @Cron(CronExpression.EVERY_30_SECONDS, {
    name: 'chat-mention-push-retry',
    timeZone: 'UTC',
  })
  async handleRetry(): Promise<void> {
    try {
      const cutoff = new Date(Date.now() - 30_000); // 30s ago
      const pending = await this.prisma.chatMention.findMany({
        where: {
          notify: true,
          notifiedAt: null,
          createdAt: { lt: cutoff },
        },
        take: 50,
      });
      if (pending.length === 0) return;
      this.logger.debug(
        `chat-mention-push-retry: re-enqueuing ${pending.length} mention(s)`,
      );
      for (const m of pending) {
        // Re-enqueue so the batch + flush path runs. If the recipient
        // came online since the original attempt, the enqueue path's
        // skip-if-online check will mark it notified and skip the push.
        await this.enqueueMention(m.id);
      }
    } catch (err: any) {
      this.logger.error(
        `chat-mention-push-retry failed: ${err?.message}`,
        err?.stack,
      );
    }
  }
}

interface PendingMention {
  mentionId: string;
  messageId: string;
  senderName: string;
  groupId: string | null;
}
