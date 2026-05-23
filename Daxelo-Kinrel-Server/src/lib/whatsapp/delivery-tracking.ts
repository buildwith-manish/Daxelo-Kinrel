// DAXELO KINREL — WhatsApp Delivery Status Handler
// Pack 04: WhatsApp Platform
// Tracks message delivery status updates from WhatsApp Cloud API webhooks

import { WhatsAppDeliveryStatus } from './client'
import { db } from '@/lib/db'

// ── Event Name Mapping ──────────────────────────────────────────────

const STATUS_TO_EVENT: Record<string, string> = {
  sent: 'whatsapp.message.sent',
  delivered: 'whatsapp.message.delivered',
  read: 'whatsapp.message.read',
  failed: 'whatsapp.message.failed',
}

// ── Handle Delivery Status ──────────────────────────────────────────

export async function handleDeliveryStatus(
  status: WhatsAppDeliveryStatus,
): Promise<void> {
  const { messageId, status: deliveryStatus, timestamp, recipientId } = status

  const eventName =
    STATUS_TO_EVENT[deliveryStatus] ?? `whatsapp.message.${deliveryStatus}`

  // Build metadata from the delivery status
  const metadata: Record<string, unknown> = {
    timestamp,
    recipientId,
  }

  // For failed status, include error information if available
  if (deliveryStatus === 'failed') {
    // WhatsApp may include error details in the status object
    const errorData = (status as WhatsAppDeliveryStatus & { errors?: Array<{ code: number; title: string; message: string }> }).errors
    if (errorData && errorData.length > 0) {
      metadata.errorCode = errorData[0].code
      metadata.errorTitle = errorData[0].title
      metadata.errorMessage = errorData[0].message
    }
  }

  // Try to find the user by the recipient phone number
  const normalizedPhone = recipientId.replace(/^\+91/, '').replace(/^\+/, '')
  const user = await db.user.findFirst({
    where: { phone: { contains: normalizedPhone } },
    select: { id: true },
  })

  // Try to find the associated notification by messageId
  let familyId: string | null = null
  let templateId: string | null = null

  // Look up the notification update that corresponds to this message
  const notificationUpdate = await db.notificationUpdate.findFirst({
    where: {
      channel: 'whatsapp',
      status: 'delivered',
    },
    include: {
      notification: {
        select: { familyId: true },
      },
    },
    orderBy: { createdAt: 'desc' },
  })

  if (notificationUpdate?.notification?.familyId) {
    familyId = notificationUpdate.notification.familyId
  }

  // Check WhatsAppTemplate for templateId matching
  const templateAnalytics = await db.whatsAppAnalytics.findFirst({
    where: {
      messageId,
      event: 'whatsapp.message.sent',
    },
    select: { templateId: true, familyId: true },
  })

  if (templateAnalytics?.templateId) {
    templateId = templateAnalytics.templateId
  }
  if (templateAnalytics?.familyId) {
    familyId = templateAnalytics.familyId
  }

  // Record the analytics event
  try {
    await db.whatsAppAnalytics.create({
      data: {
        event: eventName,
        userId: user?.id ?? null,
        familyId: familyId ?? null,
        messageId,
        templateId,
        metadata: JSON.stringify(metadata),
      },
    })
  } catch (error) {
    console.error(
      `[DeliveryTracking] Failed to record ${eventName} for message ${messageId}:`,
      error,
    )
  }

  // Update the notification delivery tracking if applicable
  if (deliveryStatus === 'delivered' || deliveryStatus === 'read') {
    try {
      // Find the latest pending notification update for this user on WhatsApp
      const pendingUpdate = await db.notificationUpdate.findFirst({
        where: {
          channel: 'whatsapp',
          status: 'pending',
          notification: user?.id
            ? { userId: user.id }
            : undefined,
        },
        orderBy: { createdAt: 'desc' },
      })

      if (pendingUpdate) {
        await db.notificationUpdate.update({
          where: { id: pendingUpdate.id },
          data: { status: deliveryStatus === 'read' ? 'read' : 'delivered' },
        })
      }
    } catch (error) {
      console.error(
        `[DeliveryTracking] Failed to update notification status for message ${messageId}:`,
        error,
      )
    }
  }

  // Log for monitoring
  console.log(
    `[DeliveryTracking] ${deliveryStatus.toUpperCase()} — messageId: ${messageId}, recipient: ${recipientId}`,
  )
}

// ── Batch Delivery Status Handler ───────────────────────────────────

export async function handleBatchDeliveryStatuses(
  statuses: WhatsAppDeliveryStatus[],
): Promise<void> {
  for (const status of statuses) {
    try {
      await handleDeliveryStatus(status)
    } catch (error) {
      console.error(
        `[DeliveryTracking] Error processing delivery status for ${status.messageId}:`,
        error,
      )
      // Continue processing other statuses even if one fails
    }
  }
}

// ── Get Delivery Metrics ────────────────────────────────────────────

export async function getDeliveryMetrics(
  since: Date,
): Promise<{
  sent: number
  delivered: number
  read: number
  failed: number
  deliveryRate: number
  readRate: number
}> {
  const [sent, delivered, read, failed] = await Promise.all([
    db.whatsAppAnalytics.count({
      where: { event: 'whatsapp.message.sent', createdAt: { gte: since } },
    }),
    db.whatsAppAnalytics.count({
      where: { event: 'whatsapp.message.delivered', createdAt: { gte: since } },
    }),
    db.whatsAppAnalytics.count({
      where: { event: 'whatsapp.message.read', createdAt: { gte: since } },
    }),
    db.whatsAppAnalytics.count({
      where: { event: 'whatsapp.message.failed', createdAt: { gte: since } },
    }),
  ])

  return {
    sent,
    delivered,
    read,
    failed,
    deliveryRate: sent > 0 ? (delivered / sent) * 100 : 0,
    readRate: delivered > 0 ? (read / delivered) * 100 : 0,
  }
}
