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
      // Group by (familyId, recipientUserId) so we can batch.
      const batches = new Map<
        string, // `${familyId}:${recipientUserId}`
        {
          familyId: string;
          recipientUserId: string;
          familyName: string;
          messages: typeof unnotifiedMessages;
        }
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

          const key = `${msg.familyId}:${m.userId}`;
          let batch = batches.get(key);
          if (!batch) {
            let familyName = familyNameCache.get(msg.familyId);
            if (familyName === undefined) {
              const fam = await this.prisma.family.findUnique({
                where: { id: msg.familyId },
                select: { name: true },
              });
              familyName = fam?.name ?? 'your family';
              familyNameCache.set(msg.familyId, familyName);
            }
            batch = {
              familyId: msg.familyId,
              recipientUserId: m.userId,
              familyName,
              messages: [],
            };
            batches.set(key, batch);
          }
          batch.messages.push(msg);
        }
      }

      if (batches.size === 0) {
        // All un-notified messages were already read by everyone — mark
        // them notified so we don't re-process next run.
        const allIds = unnotifiedMessages.map((m) => m.id);
        await this.markNotified(allIds);
        this.logger.log(
          `Batched-push job: ${allIds.length} message(s) already read by all recipients — marked notified=true`,
        );
        return;
      }

      // 3. Send one FCM push per batch + create an in-app Notification row.
      let pushSent = 0;
      let pushSkipped = 0;
      const allNotifiedIds: string[] = [];

      for (const batch of batches.values()) {
        const messageCount = batch.messages.length;
        const senderName = batch.messages[0].senderName;
        const previewContent = batch.messages[0].content.slice(0, 50);

        const title =
          messageCount === 1
            ? `${senderName} in ${batch.familyName}`
            : `${senderName} sent ${messageCount} messages in ${batch.familyName}`;
        const body =
          messageCount === 1
            ? previewContent
            : `${messageCount} new messages. Latest: ${previewContent}`;

        try {
          const sent = await this.fcmService.sendToUser(batch.recipientUserId, {
            title,
            body,
            data: {
              type: 'chat_message_batch',
              familyId: batch.familyId,
              familyName: batch.familyName,
              messageCount: String(messageCount),
              senderId: batch.messages[0].senderId,
              senderName,
              // Deep-link to the family chat screen
              actionUrl: `kinrel://family/${batch.familyId}/chat`,
            },
          });

          if (sent) {
            pushSent++;
          } else {
            pushSkipped++;
          }

          // Create an in-app Notification row so the user sees the
          // unread count in the app's notification center even if FCM
          // was unavailable.
          await this.createInAppNotification(
            batch.recipientUserId,
            batch.familyId,
            title,
            body,
            batch.messages[0].senderId,
            batch.messages[0].senderName,
          );
        } catch (err: any) {
          this.logger.error(
            `Batched-push failed for user ${batch.recipientUserId} family ${batch.familyId}: ${err?.message}`,
          );
          pushSkipped++;
        }

        // Mark all messages in this batch as notified, regardless of
        // whether the FCM push succeeded. We don't want to re-push the
        // same batch every 5 minutes if FCM is down — the in-app
        // notification row is the fallback.
        for (const msg of batch.messages) {
          allNotifiedIds.push(msg.id);
        }
      }

      await this.markNotified(allNotifiedIds);

      this.logger.log(
        `Batched-push job complete: sent ${pushSent} push(es), skipped ${pushSkipped} (FCM unavailable or failed), marked ${allNotifiedIds.length} message(s) notified=true`,
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
}
