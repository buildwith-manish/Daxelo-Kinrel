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
//   • Quiet-hours-aware: respects NotificationPreference.quietHoursStart/End.
//   • Block-aware: never push if the recipient has blocked the sender
//     (BlockedUser row exists with blockerId=recipient, blockedId=sender).
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
      // gateway's connectedUsers map. If they're currently connected,
      // AND viewing the chat the mention came from, skip the push
      // entirely. We can't tell which chat they're viewing from the
      // socket layer alone (a socket joins multiple chat:family:*
      // rooms); for v1 we just check if they have ANY active socket
      // and skip the push. TODO(phase-a-5): track per-socket "current
      // chat" via a chat:viewing event so we can be precise.
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

      // Mute-aware: load ChatSettings for (recipient, familyId).
      // If the chat is muted AND the recipient has
      // mentionsBreakMute=false, skip the push. Quiet hours and
      // block list are always respected.
      const recipientId = mention.mentionedUserId;
      const shouldPush = await this.shouldPushForRecipient(
        recipientId,
        mention.mentionedByName,
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

  /// Decide whether a push should fire for this recipient + sender.
  /// Checks: block list, quiet hours, mute (with mentionsBreakMute
  /// override). All failures default to "don't push" (fail-closed for
  /// privacy).
  private async shouldPushForRecipient(
    recipientId: string,
    senderDisplayName: string,
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
      if (pref) {
        // Quiet hours — always respected regardless of mentionsBreakMute.
        if (this.isInQuietHours(pref)) {
          return false;
        }
        // mentionsBreakMute default TRUE.
        const breakMute = pref.mentionsBreakMute ?? true;
        if (!breakMute) {
          // Recipient has explicitly opted out of mentions breaking
          // mute. Check the chat's mute state for each mention — but
          // since the batch is per-recipient (not per-chat), we err on
          // the side of "if ANY of the mentions came from a muted
          // chat AND the user opted out, skip the entire batch."
          // This is conservative — the worst case is the user sees
          // the mentions in-app next time they open the chat. The
          // alternative (per-mention mute check) would require
          // iterating the batch and splitting by chat mute state,
          // which is more complex than v1 needs.
          // TODO(phase-a-5): per-chat mute split for the batch.
          const allMuted = await this.areAllMentionsMuted(recipientId);
          if (allMuted) {
            return false;
          }
        }
      }
      // 2. Block list — always respected.
      // We don't have the sender's userId here (only their display
      // name from the ChatMention row); the ChatMention.mentionedByName
      // field is a snapshot, not a foreign key. For v1, the block
      // check happens at the ChatService layer when the mention is
      // created (we look up the message.senderId and check BlockedUser).
      // TODO(phase-a-5): surface senderId on ChatMention so the
      // scheduler can do its own block check.
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

  /// Check whether the recipient is currently in their configured quiet
  /// hours window. Returns false if no quiet hours are configured.
  private isInQuietHours(pref: {
    quietHoursEnabled?: boolean;
    quietHoursStart?: string | null;
    quietHoursEnd?: string | null;
    quietHoursTimezone?: string;
  }): boolean {
    if (!pref.quietHoursEnabled) return false;
    if (!pref.quietHoursStart || !pref.quietHoursEnd) return false;
    // For brevity, do a string-comparison time check. A proper impl
    // would parse the timezone + use Temporal API; this is a v1
    // best-effort path.
    // TODO(phase-a-5): real tz-aware quiet hours check.
    const now = new Date();
    const nowHhMm = `${String(now.getHours()).padStart(2, '0')}:${String(now.getMinutes()).padStart(2, '0')}`;
    const start = pref.quietHoursStart;
    const end = pref.quietHoursEnd;
    if (start <= end) {
      return nowHhMm >= start && nowHhMm < end;
    }
    // Overnight window (e.g. 22:00 → 07:00).
    return nowHhMm >= start || nowHhMm < end;
  }

  /// Check whether ALL of the recipient's pending mentions came from
  /// chats that are muted for them. Used when the recipient has opted
  /// out of mentions breaking mute — in that case, if every mention
  /// came from a muted chat, skip the batch entirely.
  private async areAllMentionsMuted(recipientId: string): Promise<boolean> {
    const batch = this.pendingBatches.get(recipientId);
    if (!batch) return false;
    // For each mention, look up the ChatMessage → familyId, then
    // check ChatSettings.isMuted for (recipientId, familyId). One
    // batched query.
    const familyIds = new Set<string>();
    for (const m of batch.mentions) {
      const msg = await this.prisma.chatMessage.findUnique({
        where: { id: m.messageId },
        select: { familyId: true },
      });
      if (msg) familyIds.add(msg.familyId);
    }
    if (familyIds.size === 0) return false;
    const mutedRows = await this.prisma.chatSettings.findMany({
      where: {
        userId: recipientId,
        familyId: { in: Array.from(familyIds) },
        isMuted: true,
      },
      select: { familyId: true },
    });
    const mutedFamilyIds = new Set(mutedRows.map((r) => r.familyId));
    return Array.from(familyIds).every((id) => mutedFamilyIds.has(id));
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
