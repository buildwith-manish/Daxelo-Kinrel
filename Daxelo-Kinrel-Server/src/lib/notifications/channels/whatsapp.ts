// DAXELO KINREL — WhatsApp Notification Channel Adapter
// Pack 04: WhatsApp Platform — Notification Pipeline

import { whatsappClient } from '@/lib/whatsapp/client';
import { db } from '@/lib/db';
import type { NotificationEvent, NotificationTemplate } from '../event-schema';

/**
 * Result of a WhatsApp notification send attempt.
 */
export interface WhatsAppSendResult {
  success: boolean;
  messageId?: string;
  error?: string;
  skipped?: boolean;
  skipReason?: string;
}

/**
 * Send a notification via WhatsApp Business API.
 *
 * Performs the following checks before sending:
 * 1. User must have a phone number on file
 * 2. User must have opted in to WhatsApp notifications (WhatsAppConsent)
 * 3. Current time must not be within user's configured quiet hours
 * 4. User must not have exceeded their max-per-day WhatsApp notification limit
 *
 * After successful send, records the delivery in NotificationUpdate table.
 */
export async function sendWhatsAppNotification(
  userId: string,
  notificationId: string,
  template: NotificationTemplate,
  event: NotificationEvent,
): Promise<WhatsAppSendResult> {
  try {
    // ── 1. Fetch user with WhatsApp consent record ──────────────────────
    const user = await db.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        phone: true,
        preferredLanguage: true,
        whatsappConsent: true,
        notificationPrefs: {
          where: { eventType: event.type },
          take: 1,
        },
      },
    });

    if (!user) {
      return {
        success: false,
        skipped: true,
        skipReason: `User not found: ${userId}`,
      };
    }

    // ── 2. Check phone number availability ──────────────────────────────
    if (!user.phone) {
      return {
        success: false,
        skipped: true,
        skipReason: `User has no phone number: ${userId}`,
      };
    }

    // ── 3. Check WhatsApp opt-in status ─────────────────────────────────
    const consent = user.whatsappConsent;
    if (!consent || !consent.optedIn) {
      return {
        success: false,
        skipped: true,
        skipReason: `User has not opted in to WhatsApp: ${userId}`,
      };
    }

    // ── 4. Check quiet hours ────────────────────────────────────────────
    const prefs = user.notificationPrefs[0];
    if (prefs && isInQuietHours(prefs.quietHoursStart, prefs.quietHoursEnd, prefs.quietHoursTimezone)) {
      return {
        success: false,
        skipped: true,
        skipReason: `User is in quiet hours: ${userId}`,
      };
    }

    // ── 5. Check max-per-day limit ──────────────────────────────────────
    const maxPerDay = prefs?.maxPerDay ?? 10;
    const todayStart = new Date();
    todayStart.setHours(0, 0, 0, 0);

    const todayWhatsAppCount = await db.notificationUpdate.count({
      where: {
        notification: { userId },
        channel: 'whatsapp',
        status: 'delivered',
        createdAt: { gte: todayStart },
      },
    });

    if (todayWhatsAppCount >= maxPerDay) {
      return {
        success: false,
        skipped: true,
        skipReason: `User exceeded WhatsApp daily limit (${todayWhatsAppCount}/${maxPerDay}): ${userId}`,
      };
    }

    // ── 6. Check that WhatsApp client is configured ─────────────────────
    if (!whatsappClient.isConfigured()) {
      // In development/staging, log and record as failed rather than throwing
      console.warn('[WhatsAppChannel] WhatsApp client not configured, skipping send');

      await db.notificationUpdate.create({
        data: {
          notificationId,
          channel: 'whatsapp',
          status: 'failed',
          error: 'WhatsApp client not configured (missing env vars)',
        },
      });

      return {
        success: false,
        error: 'WhatsApp client not configured',
      };
    }

    // ── 7. Send via WhatsApp client ─────────────────────────────────────
    const messageBody = `*${template.title}*\n\n${template.body}\n\n— Daxelo Kinrel`;
    const sendResponse = await whatsappClient.sendTextMessage(user.phone, messageBody);

    // ── 8. Record successful delivery ───────────────────────────────────
    await db.notificationUpdate.create({
      data: {
        notificationId,
        channel: 'whatsapp',
        status: 'delivered',
      },
    });

    // ── 9. Record analytics event ───────────────────────────────────────
    await db.whatsAppAnalytics.create({
      data: {
        event: 'whatsapp.message.sent',
        userId,
        familyId: event.familyId ?? null,
        messageId: sendResponse.messageId,
        metadata: JSON.stringify({
          eventType: event.type,
          priority: event.priority,
          templateTitle: template.title,
        }),
      },
    });

    return {
      success: true,
      messageId: sendResponse.messageId,
    };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    console.error(`[WhatsAppChannel] Failed to send notification to user ${userId}:`, errorMessage);

    // Record failure in NotificationUpdate
    try {
      await db.notificationUpdate.create({
        data: {
          notificationId,
          channel: 'whatsapp',
          status: 'failed',
          error: errorMessage,
        },
      });
    } catch (dbError) {
      console.error('[WhatsAppChannel] Failed to record delivery failure:', dbError);
    }

    return {
      success: false,
      error: errorMessage,
    };
  }
}

/**
 * Check if the current time falls within the user's quiet hours window.
 *
 * Quiet hours span from quietHoursStart to quietHoursEnd in the user's timezone.
 * Handles overnight windows (e.g., 22:00–08:00) by checking if current hour
 * is >= start OR < end.
 *
 * Default timezone is Asia/Kolkata (IST) for the Indian user base.
 */
export function isInQuietHours(
  quietHoursStart: string | null | undefined,
  quietHoursEnd: string | null | undefined,
  timezone: string = 'Asia/Kolkata',
): boolean {
  if (!quietHoursStart || !quietHoursEnd) {
    return false;
  }

  try {
    const now = new Date();
    const formatter = new Intl.DateTimeFormat('en-US', {
      timeZone: timezone,
      hour: 'numeric',
      hour12: false,
    });

    const localHour = parseInt(formatter.format(now), 10);
    const startHour = parseInt(quietHoursStart.split(':')[0], 10);
    const endHour = parseInt(quietHoursEnd.split(':')[0], 10);

    if (isNaN(localHour) || isNaN(startHour) || isNaN(endHour)) {
      return false;
    }

    // Overnight window: e.g., 22:00–08:00
    if (startHour > endHour) {
      return localHour >= startHour || localHour < endHour;
    }

    // Same-day window: e.g., 13:00–15:00
    return localHour >= startHour && localHour < endHour;
  } catch {
    return false;
  }
}
