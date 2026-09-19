import { Injectable, Logger } from '@nestjs/common';
import { Cron } from '@nestjs/schedule';
import { PrismaService } from '../../prisma/prisma.service';
import { FcmService } from '../notifications/fcm.service';

/**
 * ChatPushScheduler — smart batched push notifications for unread chat
 * messages.
 *
 * Runs every 5 minutes via @Cron. For each family chat, finds messages
 * that are:
 *   • older than 2 minutes (gives the recipient time to see them in-app
 *     before we push — avoids notifying for messages they're already
 *     reading in the open chat screen)
 *   • marked notified = false (so we don't re-notify on subsequent runs)
 *   • NOT read by the recipient (readBy array doesn't contain them)
 *   • NOT sent by the recipient (you don't get notified for your own
 *     messages)
 *
 * Groups messages per recipient per family, sends ONE batched FCM push
 * ("You have 3 new messages from Manish in Sharma Family"), then marks
 * all those messages as notified = true.
 *
 * Uses the existing FcmService (Firebase Cloud Messaging) which handles
 * FCM token lookup, retry, and invalid-token cleanup. If Firebase
 * credentials aren't configured, the push is silently skipped (the
 * in-app Notification row is still created so the user sees it next
 * time they open the app).
 */
@Injectable()
export class ChatPushScheduler {
  private readonly logger = new Logger(ChatPushScheduler.name);

  /// The "unread grace period" — messages younger than this (in minutes)
  /// are NOT pushed, to avoid notifying for messages the recipient is
  /// already reading in the open chat. 2 minutes matches the user spec.
  private readonly gracePeriodMinutes = 2;

  constructor(
    private readonly prisma: PrismaService,
    private readonly fcmService: FcmService,
  ) {}

  /// Every 5 minutes. Picks up un-notified messages older than 2 minutes
  /// and sends batched FCM pushes per recipient per family.
  @Cron('*/5 * * * *', {
    name: 'chat-batched-push',
    timeZone: 'UTC',
  })
  async handleBatchedPush() {
    const now = new Date();
    const cutoff = new Date(now.getTime() - this.gracePeriodMinutes * 60 * 1000);

    try {
      // 1. Find all un-notified messages older than the grace period.
      // We fetch them grouped by (familyId, recipientUserId) so we can
      // batch the FCM push per recipient per family.
      //
      // The "recipient" of a message is every family member EXCEPT the
      // sender AND except users who have already read it (in readBy).
      // We resolve recipients by joining FamilyMember on familyId.
      const unnotifiedMessages = await this.prisma.chatMessage.findMany({
        where: {
          notified: false,
          createdAt: { lt: cutoff },
          isDeletedForEveryone: false,
        },
        select: {
          id: true,
          familyId: true,
          senderId: true,
          senderName: true,
          content: true,
          createdAt: true,
          readBy: true,
        },
        orderBy: { createdAt: 'asc' },
      });

      if (unnotifiedMessages.length === 0) {
        return; // nothing to do — skip the log to avoid noise
      }

      this.logger.log(
        `Batched-push job: ${unnotifiedMessages.length} un-notified message(s) older than ${this.gracePeriodMinutes}min`,
      );

      // 2. For each message, find the recipients (family members who
      //    haven't read it and aren't the sender).
      //
      // Feature 2: CROSS-CHAT GROUPING. Previously we grouped by
      // (familyId, recipientUserId) — one push per chat per recipient.
      // Now we group by recipientUserId ONLY — one push per recipient
      // across ALL their chats. So if Manish has 3 unread messages in
      // the "Sharmas" chat + 2 in the "Patels" chat, he gets ONE push:
      // "3 new messages from Mama ji and 2 others" (deep-link to the
      // chat with the most recent message).
      const perRecipient = new Map<
        string, // recipientUserId
        Array<{
          familyId: string;
          familyName: string;
          senderId: string;
          senderName: string;
          messageId: string;
          content: string;
          createdAt: Date;
        }>
      >();

      // Cache family member lookups + family name lookups to avoid N queries.
      const familyMembersCache = new Map<string, { userId: string }[]>();
      const familyNameCache = new Map<string, string>();

      for (const msg of unnotifiedMessages) {
        let members = familyMembersCache.get(msg.familyId);
        if (!members) {
          members = await this.prisma.familyMember.findMany({
            where: { familyId: msg.familyId },
            select: { userId: true },
          });
          familyMembersCache.set(msg.familyId, members);
        }

        for (const m of members) {
          // Skip the sender.
          if (m.userId === msg.senderId) continue;
          // Skip users who have already read this message.
          if (msg.readBy.includes(m.userId)) continue;

          let familyName = familyNameCache.get(msg.familyId);
          if (familyName === undefined) {
            const fam = await this.prisma.family.findUnique({
              where: { id: msg.familyId },
              select: { name: true },
            });
            familyName = fam?.name ?? 'your family';
            familyNameCache.set(msg.familyId, familyName);
          }

          const list = perRecipient.get(m.userId) ?? [];
          list.push({
            familyId: msg.familyId,
            familyName,
            senderId: msg.senderId,
            senderName: msg.senderName,
            messageId: msg.id,
            content: msg.content,
            createdAt: msg.createdAt,
          });
          perRecipient.set(m.userId, list);
        }
      }

      if (perRecipient.size === 0) {
        // All un-notified messages were already read by everyone — mark
        // them notified so we don't re-process next run.
        const allIds = unnotifiedMessages.map((m) => m.id);
        await this.markNotified(allIds);
        this.logger.log(
          `Batched-push job: ${allIds.length} message(s) already read by all recipients — marked notified=true`,
        );
        return;
      }

      // 3. Send ONE FCM push per recipient (across all their chats).
      // Build a grouped title like:
      //   • 1 message: "Mama ji: hello beta"
      //   • N messages, 1 chat: "Mama ji sent 3 messages in Sharmas"
      //   • N messages, M chats: "3 new messages from Mama ji and 2 others"
      let pushSent = 0;
      let pushSkipped = 0;
      const allNotifiedIds: string[] = [];

      for (const [recipientUserId, messages] of perRecipient.entries()) {
        // Sort by createdAt desc so the most recent message is the preview.
        messages.sort((a, b) => b.createdAt.getTime() - a.createdAt.getTime());
        const totalMessages = messages.length;
        const distinctChats = new Set(messages.map((m) => m.familyId)).size;
        const distinctSenders = new Set(messages.map((m) => m.senderId)).size;
        const latest = messages[0];
        const previewContent = latest.content.slice(0, 50);

        // ── Feature 6: per-chat mute + quiet hours check ──────────────
        // Skip the FCM push if the recipient has muted ALL the chats these
        // messages came from, OR if the recipient is in their quiet-hours
        // window. The in-app Notification row is still created (so the
        // user sees the unread count in the app's notification center).
        const skipPush = await this._shouldSkipPush(recipientUserId, messages);
        if (skipPush) {
          pushSkipped++;
          // Still mark the messages as notified so we don't re-evaluate them
          // next run. The in-app notification row is the fallback.
          for (const msg of messages) {
            allNotifiedIds.push(msg.messageId);
          }
          // Create the in-app notification row (best-effort)
          await this.createInAppNotification(
            recipientUserId,
            latest.familyId,
            latest.senderName,
            previewContent,
            latest.senderId,
            latest.senderName,
          ).catch(() => {});
          continue;
        }

        let title: string;
        let body: string;
        if (totalMessages === 1) {
          title = `${latest.senderName}`;
          body = previewContent;
        } else if (distinctChats === 1) {
          // All from the same chat — "Mama ji sent 3 messages in Sharmas"
          title = `${latest.senderName} sent ${totalMessages} messages in ${latest.familyName}`;
          body = `${totalMessages} new messages. Latest: ${previewContent}`;
        } else {
          // Cross-chat grouping — "3 new messages from Mama ji and 2 others"
          const senderNames = [...new Set(messages.map((m) => m.senderName))].slice(0, 2);
          const firstSender = senderNames[0];
          const otherCount = distinctSenders - 1;
          if (otherCount > 0) {
            title = `${totalMessages} new messages from ${firstSender} and ${otherCount} other${otherCount !== 1 ? 's' : ''}`;
          } else {
            title = `${totalMessages} new messages from ${firstSender}`;
          }
          body = `Across ${distinctChats} chat${distinctChats !== 1 ? 's' : ''}. Latest: ${previewContent}`;
        }

        try {
          const sent = await this.fcmService.sendToUser(recipientUserId, {
            title,
            body,
            data: {
              type: 'chat_message_batch',
              // Feature 2: deep-link payload. The Flutter
              // push_notification_service resolves 'chat_message_batch'
              // type → /family/<familyId>/chat. We point at the chat
              // with the most recent message so tapping the notification
              // opens the most relevant conversation.
              familyId: latest.familyId,
              familyName: latest.familyName,
              messageCount: String(totalMessages),
              distinctChats: String(distinctChats),
              senderId: latest.senderId,
              senderName: latest.senderName,
              actionUrl: `kinrel://family/${latest.familyId}/chat`,
            },
          });

          if (sent) {
            pushSent++;
          } else {
            pushSkipped++;
          }

          // Create an in-app Notification row per recipient (one row
          // summarizing all their unread chats). Best-effort.
          await this.createInAppNotification(
            recipientUserId,
            latest.familyId,
            title,
            body,
            latest.senderId,
            latest.senderName,
          );
        } catch (err: any) {
          this.logger.error(
            `Batched-push failed for user ${recipientUserId}: ${err?.message}`,
          );
          pushSkipped++;
        }

        // Mark all messages for this recipient as notified.
        for (const msg of messages) {
          allNotifiedIds.push(msg.messageId);
        }
      }

      await this.markNotified(allNotifiedIds);

      this.logger.log(
        `Batched-push job complete: sent ${pushSent} push(es) to ${perRecipient.size} recipient(s), ` +
          `skipped ${pushSkipped} (FCM unavailable or failed), marked ${allNotifiedIds.length} message(s) notified=true`,
      );
    } catch (err: any) {
      this.logger.error(
        `Batched-push job failed: ${err?.message}`,
        err?.stack,
      );
    }
  }

  /// Bulk-update notified=true for a list of message IDs.
  /// Uses updateMany for a single SQL round-trip.
  private async markNotified(messageIds: string[]) {
    if (messageIds.length === 0) return;
    await this.prisma.chatMessage.updateMany({
      where: { id: { in: messageIds } },
      data: { notified: true, updatedAt: new Date() },
    });
  }

  /// Insert a Notification row so the user sees the unread chat count
  /// in the app's notification center. Best-effort — failure is logged
  /// but doesn't fail the push.
  private async createInAppNotification(
    recipientUserId: string,
    familyId: string,
    title: string,
    body: string,
    senderId: string,
    senderName: string,
  ) {
    try {
      await this.prisma.notification.create({
        data: {
          id: `chat_notif_${Date.now()}_${recipientUserId}_${familyId}`,
          userId: recipientUserId,
          eventType: 'chat_message',
          title,
          body,
          familyId,
          actionUrl: `kinrel://family/${familyId}/chat`,
          priority: 'normal',
          read: false,
          channels: ['push', 'inApp'],
          createdAt: new Date(),
          updatedAt: new Date(),
        },
      });
    } catch (err: any) {
      this.logger.warn(
        `In-app notification insert failed for ${recipientUserId}: ${err?.message}`,
      );
    }
  }

  /// Feature 6: check if the push should be skipped for this recipient.
  /// Returns true if:
  ///   1. The recipient has muted ALL the chats these messages came from
  ///      (ChatSettings.isMuted = true for every familyId in the batch), OR
  ///   2. The recipient is currently in their quiet-hours window
  ///      (NotificationPreference.quietHoursStart/End covers the current time).
  ///
  /// In either case, the in-app Notification row is still created (so the
  /// user sees the unread count when they open the app), but the FCM push
  /// is suppressed.
  ///
  /// NOTE: when only SOME chats are muted, we still push (for the unmuted
  /// ones). A future improvement would split the batch + push only the
  /// unmuted subset.
  private async _shouldSkipPush(
    recipientUserId: string,
    messages: Array<{ familyId: string; senderId: string }>,
  ): Promise<boolean> {
    try {
      // 1. Check per-chat mute. If ALL messages are from muted chats, skip.
      const distinctFamilyIds = [...new Set(messages.map((m) => m.familyId))];
      const chatSettings = await this.prisma.chatSettings.findMany({
        where: {
          userId: recipientUserId,
          familyId: { in: distinctFamilyIds },
          isMuted: true,
        },
        select: { familyId: true },
      });
      const mutedFamilyIds = new Set(chatSettings.map((s) => s.familyId));
      const allMuted = distinctFamilyIds.every((id) => mutedFamilyIds.has(id));
      if (allMuted) {
        this.logger.debug(
          `Skipping push for ${recipientUserId}: all ${distinctFamilyIds.length} chat(s) muted`,
        );
        return true;
      }

      // 2. Check quiet hours (global, per-user).
      const pref = await this.prisma.notificationPreference.findFirst({
        where: { userId: recipientUserId },
        select: { quietHoursStart: true, quietHoursEnd: true },
      });
      if (pref?.quietHoursStart && pref?.quietHoursEnd) {
        const inQuiet = this._isInQuietHours(pref.quietHoursStart, pref.quietHoursEnd);
        if (inQuiet) {
          this.logger.debug(
            `Skipping push for ${recipientUserId}: in quiet hours (${pref.quietHoursStart}-${pref.quietHoursEnd})`,
          );
          return true;
        }
      }

      return false;
    } catch (err: any) {
      // On error, don't skip — let the push go through (fail-open).
      this.logger.warn(
        `Mute/quiet-hours check failed for ${recipientUserId}: ${err?.message} — pushing anyway`,
      );
      return false;
    }
  }

  /// Check if the current server time falls within the quiet-hours window.
  /// Handles overnight windows (e.g. 22:00-08:00). Times are 'HH:MM' strings.
  private _isInQuietHours(start: string, end: string): boolean {
    try {
      const now = new Date();
      const currentMinutes = now.getHours() * 60 + now.getMinutes();
      const [startH, startM] = start.split(':').map(Number);
      const [endH, endM] = end.split(':').map(Number);
      const startMinutes = startH * 60 + startM;
      const endMinutes = endH * 60 + endM;

      if (startMinutes <= endMinutes) {
        // Same-day window, e.g. 09:00-17:00
        return currentMinutes >= startMinutes && currentMinutes <= endMinutes;
      } else {
        // Overnight window, e.g. 22:00-08:00
        return currentMinutes >= startMinutes || currentMinutes <= endMinutes;
      }
    } catch {
      return false;
    }
  }
}
