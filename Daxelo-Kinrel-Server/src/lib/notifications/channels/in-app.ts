// DAXELO KINREL — In-App Notification Channel Adapter
// Pack 04: WhatsApp Platform — Notification Pipeline

import { db } from '@/lib/db';
import type { NotificationEvent, NotificationTemplate } from '../event-schema';

/**
 * Result of an in-app notification delivery attempt.
 */
export interface InAppSendResult {
  success: boolean;
  notificationData?: InAppNotificationData;
  error?: string;
}

/**
 * Shape of in-app notification data returned for real-time delivery
 * via Socket.io or other real-time transport.
 */
export interface InAppNotificationData {
  id: string;
  eventType: string;
  title: string;
  body: string;
  priority: string;
  familyId: string | null;
  personId: string | null;
  actionUrl: string | null;
  createdAt: Date;
  unreadCount: number;
}

/**
 * Send an in-app notification to a user.
 *
 * This adapter:
 * 1. Records the delivery in the NotificationUpdate table
 * 2. Computes the updated unread badge count
 * 3. Returns notification data for real-time delivery via Socket.io
 *
 * The notification record is already persisted by the engine before
 * this adapter is called, so we only need to record the delivery
 * and prepare data for the real-time layer.
 */
export async function sendInAppNotification(
  userId: string,
  notificationId: string,
  template: NotificationTemplate,
  event: NotificationEvent,
): Promise<InAppSendResult> {
  try {
    // ── 1. Verify the notification record exists ────────────────────────
    const notification = await db.notification.findUnique({
      where: { id: notificationId },
      select: {
        id: true,
        eventType: true,
        title: true,
        body: true,
        priority: true,
        familyId: true,
        personId: true,
        actionUrl: true,
        createdAt: true,
      },
    });

    if (!notification) {
      await recordDeliveryStatus(notificationId, 'failed', `Notification not found: ${notificationId}`);
      return {
        success: false,
        error: `Notification not found: ${notificationId}`,
      };
    }

    // ── 2. Record delivery in NotificationUpdate table ──────────────────
    await db.notificationUpdate.create({
      data: {
        notificationId,
        channel: 'inApp',
        status: 'delivered',
      },
    });

    // ── 3. Compute unread count for badge update ────────────────────────
    const unreadCount = await db.notification.count({
      where: {
        userId,
        read: false,
      },
    });

    // ── 4. Prepare notification data for real-time delivery ─────────────
    const notificationData: InAppNotificationData = {
      id: notification.id,
      eventType: notification.eventType,
      title: notification.title,
      body: notification.body,
      priority: notification.priority,
      familyId: notification.familyId,
      personId: notification.personId,
      actionUrl: notification.actionUrl,
      createdAt: notification.createdAt,
      unreadCount,
    };

    console.log(`[InAppChannel] Delivered notification ${notificationId} to user ${userId}`, {
      eventType: event.type,
      title: template.title,
      unreadCount,
    });

    return {
      success: true,
      notificationData,
    };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    console.error(`[InAppChannel] Failed to deliver in-app notification to user ${userId}:`, errorMessage);

    await recordDeliveryStatus(notificationId, 'failed', errorMessage);

    return {
      success: false,
      error: errorMessage,
    };
  }
}

/**
 * Record a delivery status update in the NotificationUpdate table.
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
        channel: 'inApp',
        status,
        error: error ?? null,
      },
    });
  } catch (dbError) {
    console.error('[InAppChannel] Failed to record delivery status:', dbError);
  }
}
