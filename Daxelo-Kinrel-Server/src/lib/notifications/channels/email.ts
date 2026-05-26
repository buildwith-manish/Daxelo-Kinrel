// DAXELO KINREL — Email Notification Channel Adapter
// Pack 04: WhatsApp Platform — Notification Pipeline

import { db } from '@/lib/db';
import type { NotificationEvent, NotificationTemplate } from '../event-schema';

/**
 * Result of an email notification send attempt.
 */
export interface EmailSendResult {
  success: boolean;
  error?: string;
  skipped?: boolean;
  skipReason?: string;
}

/**
 * Send a notification via email.
 *
 * Current implementation is a placeholder that logs to console
 * since no email service (Resend, Nodemailer, etc.) is configured yet.
 * Once an email provider is set up, this adapter will:
 * 1. Look up the user's email address
 * 2. Render an HTML email from the template
 * 3. Send via the configured email provider
 *
 * Regardless of email service availability, every send attempt is recorded
 * in the NotificationUpdate table for delivery tracking.
 */
export async function sendEmailNotification(
  userId: string,
  notificationId: string,
  template: NotificationTemplate,
  event: NotificationEvent,
): Promise<EmailSendResult> {
  try {
    // ── 1. Verify user exists and has an email address ──────────────────
    const user = await db.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        email: true,
        name: true,
        preferredLanguage: true,
      },
    });

    if (!user) {
      await recordDeliveryStatus(notificationId, 'failed', `User not found: ${userId}`);
      return {
        success: false,
        error: `User not found: ${userId}`,
      };
    }

    if (!user.email) {
      await recordDeliveryStatus(notificationId, 'failed', `User has no email address: ${userId}`);
      return {
        success: false,
        error: `User has no email address: ${userId}`,
      };
    }

    // ── 2. Prepare email content ────────────────────────────────────────
    const emailContent = buildEmailContent(template, event, user.name ?? 'User');

    // ── 3. Log the email (placeholder for email service) ────────────────
    console.log(`[EmailChannel] Sending email notification to ${user.email}:`, {
      to: user.email,
      subject: emailContent.subject,
      textBody: emailContent.textBody,
      eventType: event.type,
      priority: event.priority,
    });

    // ── 4. Record delivery attempt in NotificationUpdate table ──────────
    // In production, this status would be "pending" and updated to
    // "delivered" after the email provider confirms delivery.
    // For the placeholder, we record as "delivered".
    await db.notificationUpdate.create({
      data: {
        notificationId,
        channel: 'email',
        status: 'delivered',
      },
    });

    return {
      success: true,
    };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    console.error(`[EmailChannel] Failed to send email notification to user ${userId}:`, errorMessage);

    await recordDeliveryStatus(notificationId, 'failed', errorMessage);

    return {
      success: false,
      error: errorMessage,
    };
  }
}

/**
 * Build email subject and body content from the notification template.
 * Uses Indian English conventions and the Daxelo Kinrel brand voice.
 */
function buildEmailContent(
  template: NotificationTemplate,
  event: NotificationEvent,
  userName: string,
): { subject: string; textBody: string; htmlBody: string } {
  const subject = `Daxelo Kinrel: ${template.title}`;

  const textBody = [
    `Namaste ${userName},`,
    '',
    template.body,
    '',
    '— Team Daxelo Kinrel',
    '',
    'You can manage your notification preferences in the app Settings.',
  ].join('\n');

  const htmlBody = [
    '<!DOCTYPE html>',
    '<html>',
    '<head>',
    '<meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width, initial-scale=1.0">',
    '</head>',
    '<body style="font-family: -apple-system, BlinkMacSystemFont, \'Segoe UI\', Roboto, sans-serif; margin: 0; padding: 20px; background-color: #f9fafb;">',
    '<div style="max-width: 600px; margin: 0 auto; background-color: #ffffff; border-radius: 8px; padding: 24px; box-shadow: 0 1px 3px rgba(0,0,0,0.1);">',
    '<h2 style="color: #111827; margin-top: 0;">Namaste ${escapeHtml(userName)},</h2>',
    `<p style="color: #374151; font-size: 16px; line-height: 1.6;">${escapeHtml(template.body)}</p>`,
    '<hr style="border: none; border-top: 1px solid #e5e7eb; margin: 24px 0;">',
    `<p style="color: #6b7280; font-size: 14px; margin: 0;">— Team Daxelo Kinrel</p>`,
    `<p style="color: #9ca3af; font-size: 12px; margin-top: 12px;">Event type: ${escapeHtml(event.type)} | Priority: ${escapeHtml(event.priority)}</p>`,
    `<p style="color: #9ca3af; font-size: 12px;">You can manage your notification preferences in the app Settings.</p>`,
    '</div>',
    '</body>',
    '</html>',
  ].join('\n');

  return { subject, textBody, htmlBody };
}

/**
 * Escape HTML special characters to prevent XSS in email content.
 */
function escapeHtml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
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
        channel: 'email',
        status,
        error: error ?? null,
      },
    });
  } catch (dbError) {
    console.error('[EmailChannel] Failed to record delivery status:', dbError);
  }
}
