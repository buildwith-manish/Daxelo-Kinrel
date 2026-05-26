// DAXELO KINREL — Invitation Reminders
// Pack 04: WhatsApp Platform
//
// Processes pending WhatsApp invitations and sends reminders
// on day 2 and day 5 after the original invite.
// Designed to be called by a cron job scheduler.

import { db } from '@/lib/db'
import { whatsappClient } from '@/lib/whatsapp/client'
import { generateInviteDeepLink } from './deep-link'

/** Reminder schedule: day thresholds after the invite was sent */
const REMINDER_SCHEDULE = [2, 5] as const

/** Maximum number of reminders allowed per invitation */
const MAX_REMINDER_COUNT = 2

/** Look-back window: only consider invitations created within this many days */
const INVITATION_WINDOW_DAYS = 7

interface ReminderResult {
  invitationId: string
  sent: boolean
  error?: string
}

/**
 * Processes all pending WhatsApp invitations that are eligible for a reminder.
 *
 * Eligibility criteria:
 * - Invitation status is "pending"
 * - whatsappSentAt is not null (original message was sent)
 * - whatsappReminderCount < 2
 * - Created within the last 7 days
 * - Days since creation match the reminder schedule (day 2 or day 5)
 *
 * For each eligible invitation:
 * 1. Sends a reminder via WhatsApp
 * 2. Increments whatsappReminderCount
 * 3. Sets whatsappLastRemindedAt to now
 * 4. Logs an analytics event
 *
 * @returns Array of results indicating success/failure per invitation
 */
export async function processPendingReminders(): Promise<ReminderResult[]> {
  const results: ReminderResult[] = []

  const now = new Date()
  const windowStart = new Date(now.getTime() - INVITATION_WINDOW_DAYS * 24 * 60 * 60 * 1000)

  // Find all pending invitations with WhatsApp sent and under the reminder limit
  const pendingInvitations = await db.invitation.findMany({
    where: {
      status: 'pending',
      whatsappSentAt: { not: null },
      whatsappReminderCount: { lt: MAX_REMINDER_COUNT },
      createdAt: { gte: windowStart },
    },
    include: {
      family: true,
      inviter: true,
    },
  })

  for (const invitation of pendingInvitations) {
    try {
      const daysSinceInvite = getDaysSince(invitation.createdAt, now)

      // Check if today matches a reminder day
      const nextReminderDay = REMINDER_SCHEDULE[invitation.whatsappReminderCount]
      if (nextReminderDay === undefined || daysSinceInvite !== nextReminderDay) {
        continue
      }

      // Skip if no phone number to send to
      if (!invitation.recipientPhone) {
        results.push({
          invitationId: invitation.id,
          sent: false,
          error: 'No recipient phone number',
        })
        continue
      }

      // Generate deep link for the reminder
      const deepLink = generateInviteDeepLink(invitation.id, invitation.token)

      // Determine language for the reminder message
      const language = invitation.family.primaryLanguage ?? 'en'
      const reminderText = buildReminderMessage(
        invitation.inviter.name ?? 'Someone',
        invitation.family.name,
        deepLink,
        language,
        invitation.whatsappReminderCount + 1
      )

      // Send the reminder (client throws on error)
      let sendResult: { messageId: string; status: string }
      try {
        sendResult = await whatsappClient.sendTextMessage(
          invitation.recipientPhone,
          reminderText
        )
      } catch (sendError) {
        const sendErrorMessage = sendError instanceof Error ? sendError.message : 'Unknown WhatsApp error'
        console.error(
          `[ReminderProcessor] WhatsApp send failed for invitation ${invitation.id}: ${sendErrorMessage}`
        )
        results.push({
          invitationId: invitation.id,
          sent: false,
          error: sendErrorMessage,
        })
        continue
      }

      // Update invitation record
      await db.invitation.update({
        where: { id: invitation.id },
        data: {
          whatsappReminderCount: invitation.whatsappReminderCount + 1,
          whatsappLastRemindedAt: now,
        },
      })

      // Log analytics event
      await db.whatsAppAnalytics.create({
        data: {
          event: 'invite:reminder_sent',
          userId: invitation.inviterId,
          familyId: invitation.familyId,
          metadata: JSON.stringify({
            invitationId: invitation.id,
            reminderNumber: invitation.whatsappReminderCount + 1,
            daysSinceInvite,
            channel: 'whatsapp',
            messageId: sendResult.messageId,
          }),
        },
      })

      results.push({ invitationId: invitation.id, sent: true })
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Unknown error'
      console.error(
        `[ReminderProcessor] Error processing invitation ${invitation.id}: ${errorMessage}`
      )
      results.push({
        invitationId: invitation.id,
        sent: false,
        error: errorMessage,
      })
    }
  }

  return results
}

/**
 * Calculates the number of full days between a past date and now.
 */
function getDaysSince(pastDate: Date, now: Date): number {
  const diffMs = now.getTime() - pastDate.getTime()
  return Math.floor(diffMs / (24 * 60 * 60 * 1000))
}

/**
 * Builds a localized reminder message for a WhatsApp invitation.
 * Supports Hindi (hi) and English (en).
 */
function buildReminderMessage(
  inviterName: string,
  familyName: string,
  deepLink: string,
  language: string,
  reminderNumber: number
): string {
  if (language === 'hi') {
    if (reminderNumber === 1) {
      return [
        `🙏 ${inviterName} ने आपको *${familyName}* परिवार से जुड़ने का निमंत्रण भेजा है Daxelo Kinrel पर!`,
        '',
        'क्या आपने अभी तक निमंत्रण स्वीकार नहीं किया? 🤔',
        'अभी भी समय है — नीचे दिए गए लिंक पर टैप करें और अपने परिवार के पेड़ को बढ़ाएं:',
        deepLink,
        '',
        '🌱 एक परिवार। एक वृक्ष। अनंत संबंध।',
      ].join('\n')
    }
    return [
      `🙏 ${inviterName} ने आपको *${familyName}* परिवार से जुड़ने का निमंत्रण भेजा है Daxelo Kinrel पर!`,
      '',
      'यह आखिरी रिमाइंडर है! ⏰',
      'अपने परिवार के पेड़ का हिस्सा बनें — लिंक पर टैप करें:',
      deepLink,
      '',
      '🌱 एक परिवार। एक वृक्ष। अनंत संबंध।',
    ].join('\n')
  }

  // Default: English
  if (reminderNumber === 1) {
    return [
      `🙏 ${inviterName} invited you to join the *${familyName}* family on Daxelo Kinrel!`,
      '',
      'Haven\'t accepted yet? 🤔',
      'There\'s still time — tap the link below to join and grow your family tree:',
      deepLink,
      '',
      '🌱 One family. One tree. Infinite connections.',
    ].join('\n')
  }

  return [
    `🙏 ${inviterName} invited you to join the *${familyName}* family on Daxelo Kinrel!`,
    '',
    'This is your last reminder! ⏰',
    'Become part of your family tree — tap the link:',
    deepLink,
    '',
    '🌱 One family. One tree. Infinite connections.',
  ].join('\n')
}
