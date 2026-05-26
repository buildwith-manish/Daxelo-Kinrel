// DAXELO KINREL — Push Notification Channel Adapter
// Pack 04: WhatsApp Platform — Notification Pipeline

import { db } from '@/lib/db';
import type { NotificationEvent, NotificationTemplate } from '../event-schema';

/**
 * Result of a push notification send attempt.
 */
export interface PushSendResult {
  success: boolean;
  error?: string;
}

/**
 * Send a push notification to a user's device.
 *
 * Current implementation is a placeholder that logs to console
 * since FCM (Firebase Cloud Messaging) is not yet configured.
 * Once FCM is set up, this adapter will:
 * 1. Look up the user's FCM device tokens
 * 2. Send the notification payload via firebase-admin
 * 3. Handle invalid/expired tokens
 *
 * Regardless of FCM availability, every send attempt is recorded
 * in the NotificationUpdate table for delivery tracking.
 */
export async function sendPushNotification(
  userId: string,
  notificationId: string,
  template: NotificationTemplate,
  event: NotificationEvent,
): Promise<PushSendResult> {
  try {
    // ── 1. Verify user exists ───────────────────────────────────────────
    const user = await db.user.findUnique({
      where: { id: userId },
      select: { id: true, name: true },
    });

    if (!user) {
      await recordDeliveryStatus(notificationId, 'failed', `User not found: ${userId}`);
      return {
        success: false,
        error: `User not found: ${userId}`,
      };
    }

    // ── 2. Prepare push notification payload ────────────────────────────
    const pushPayload = {
      title: template.title,
      body: template.body,
      data: {
        notificationId,
        eventType: event.type,
        familyId: event.familyId ?? '',
        personId: event.personId ?? '',
        priority: event.priority,
        actorUserId: event.actorUserId,
        createdAt: event.createdAt.toISOString(),
      },
      // Android-specific channel for priority routing
      android: {
        priority: event.priority === 'critical' || event.priority === 'high' ? 'high' : 'normal',
      },
      // iOS-specific settings
      apns: {
        payload: {
          aps: {
            sound: event.priority === 'critical' ? 'critical_alert' : 'default',
            badge: await getUnreadCount(userId),
          },
        },
      },
    };

    // ── 3. Log the push notification (placeholder for FCM) ──────────────
    console.log(`[PushChannel] Sending push notification to user ${userId}:`, {
      title: template.title,
      body: template.body,
      eventType: event.type,
      priority: event.priority,
      payload: pushPayload,
    });

    // ── 4. Record delivery in NotificationUpdate table ──────────────────
    // In production, this would happen after FCM confirms delivery.
    // For now, we record as "delivered" since the placeholder always succeeds.
    await db.notificationUpdate.create({
      data: {
        notificationId,
        channel: 'push',
        status: 'delivered',
      },
    });

    return {
      success: true,
    };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    console.error(`[PushChannel] Failed to send push notification to user ${userId}:`, errorMessage);

    await recordDeliveryStatus(notificationId, 'failed', errorMessage);

    return {
      success: false,
      error: errorMessage,
    };
  }
}

/**
 * Record a delivery status update in the NotificationUpdate table.
 * Separated into its own function to allow safe error recording
 * even when the main flow fails.
 */
async function recordDeliveryStatus(
  notificationId: string,
  status: 'delivered' | 'failed' | 'pending',
  error?: string,
): Promise<void> {
  try {
    await db.notificationUpdate.create({
      data: {
        notificationId,
        channel: 'push',
        status,
        error: error ?? null,
      },
    });
  } catch (dbError) {
    console.error('[PushChannel] Failed to record delivery status:', dbError);
  }
}

/**
 * Get the current unread notification count for a user.
 * Used as the badge number in push notifications.
 */
async function getUnreadCount(userId: string): Promise<number> {
  try {
    return await db.notification.count({
      where: {
        userId,
        read: false,
      },
    });
  } catch {
    return 0;
  }
}
