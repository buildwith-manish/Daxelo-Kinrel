// DAXELO KINREL — WhatsApp Webhook Handler (STOP / Opt-out Processing)
// Pack 04: WhatsApp Platform
// Handles incoming WhatsApp messages, processes opt-out keywords,
// and routes non-opt-out messages to the bot command router

import { whatsappClient, WhatsAppMessage } from './client'
import { routeCommand } from './bot-router'
import { db } from '@/lib/db'

// ── Opt-Out Keywords ────────────────────────────────────────────────
// Multi-language opt-out keywords including Hindi
// WhatsApp Business API policy requires respecting STOP keywords

export const OPT_OUT_KEYWORDS: string[] = [
  // English
  'stop',
  'unsubscribe',
  'cancel',
  'optout',
  'opt out',
  'opt-out',
  'donotdisturb',
  'do not disturb',
  'end',
  'quit',
  'leave',
  // Hindi
  'हटाओ',
  'बंद',
  'रुको',
  'बंद करो',
  'नहीं चाहिए',
  'अनसब्सक्राइब',
  // Telugu
  'ఆపు',
  'వద్దు',
  // Tamil
  'நிறுத்து',
  'வேண்டாம்',
]

// ── Normalize Message Body ──────────────────────────────────────────

function normalizeMessage(body: string): string {
  return body.trim().toLowerCase().replace(/[\s-]+/g, ' ')
}

// ── Check Opt-Out ───────────────────────────────────────────────────

function isOptOutKeyword(body: string): boolean {
  const normalized = normalizeMessage(body)

  return OPT_OUT_KEYWORDS.some((keyword) => {
    const normalizedKeyword = normalizeMessage(keyword)
    return normalized === normalizedKeyword || normalized.includes(normalizedKeyword)
  })
}

// ── Process Opt-Out ─────────────────────────────────────────────────

async function processOptOut(from: string, messageBody: string): Promise<void> {
  const normalizedPhone = from.replace(/^\+91/, '').replace(/^\+/, '')

  // Find user by phone
  const user = await db.user.findFirst({
    where: { phone: { contains: normalizedPhone } },
  })

  if (user) {
    // Update WhatsAppConsent — opt the user out
    const existingConsent = await db.whatsAppConsent.findUnique({
      where: { userId: user.id },
    })

    if (existingConsent) {
      await db.whatsAppConsent.update({
        where: { userId: user.id },
        data: {
          optedIn: false,
          optOutAt: new Date(),
          optOutMethod: 'whatsapp_stop',
          optOutReason: messageBody.trim(),
          marketingConsent: false,
          marketingOptInAt: null,
        },
      })
    } else {
      // Create consent record with opted-out state
      await db.whatsAppConsent.create({
        data: {
          userId: user.id,
          phone: normalizedPhone,
          optedIn: false,
          optOutAt: new Date(),
          optOutMethod: 'whatsapp_stop',
          optOutReason: messageBody.trim(),
          marketingConsent: false,
        },
      })
    }

    // Also opt out from all per-template opt-ins
    await db.whatsAppOptIn.updateMany({
      where: { phone: normalizedPhone },
      data: {
        optedIn: false,
        optedInAt: null,
      },
    })

    // Record opt-out analytics event
    await db.whatsAppAnalytics.create({
      data: {
        event: 'whatsapp.opt_out.requested',
        userId: user.id,
        metadata: JSON.stringify({
          reason: messageBody.trim(),
          method: 'whatsapp_stop',
        }),
      },
    })
  } else {
    // No user account — still record the opt-out for compliance
    // Try to find consent by phone
    const consentByPhone = await db.whatsAppConsent.findFirst({
      where: { phone: normalizedPhone },
    })

    if (consentByPhone) {
      await db.whatsAppConsent.update({
        where: { id: consentByPhone.id },
        data: {
          optedIn: false,
          optOutAt: new Date(),
          optOutMethod: 'whatsapp_stop',
          optOutReason: messageBody.trim(),
          marketingConsent: false,
          marketingOptInAt: null,
        },
      })
    }

    // Opt out from per-template opt-ins by phone
    await db.whatsAppOptIn.updateMany({
      where: { phone: normalizedPhone },
      data: {
        optedIn: false,
        optedInAt: null,
      },
    })

    // Record analytics even for unknown users
    await db.whatsAppAnalytics.create({
      data: {
        event: 'whatsapp.opt_out.requested',
        metadata: JSON.stringify({
          phone: normalizedPhone,
          reason: messageBody.trim(),
          method: 'whatsapp_stop',
        }),
      },
    })
  }

  // Send confirmation message to the user
  try {
    await whatsappClient.sendTextMessage(
      from,
      "You've been unsubscribed from Daxelo Kinrel WhatsApp notifications. " +
        'You can re-enable anytime in app Settings or by typing "start".',
    )
  } catch (error) {
    console.error(
      `[WebhookHandler] Failed to send opt-out confirmation to ${from}:`,
      error,
    )
  }

  console.log(
    `[WebhookHandler] Opt-out processed for ${normalizedPhone}: "${messageBody.trim()}"`,
  )
}

// ── Handle User Query (non-opt-out messages) ────────────────────────

async function handleUserQuery(from: string, messageBody: string): Promise<void> {
  // Construct a WhatsAppMessage object and route through the bot router
  const msg: WhatsAppMessage = {
    from,
    messageId: `wa_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`,
    timestamp: Math.floor(Date.now() / 1000).toString(),
    type: 'text',
    text: { body: messageBody },
  }

  try {
    await routeCommand(msg)
  } catch (error) {
    console.error(
      `[WebhookHandler] Error routing command from ${from}:`,
      error,
    )

    // Send a fallback error message
    try {
      await whatsappClient.sendTextMessage(
        from,
        "I couldn't process that. Type 'help' for available commands.",
      )
    } catch (sendError) {
      console.error(
        `[WebhookHandler] Failed to send error message to ${from}:`,
        sendError,
      )
    }
  }
}

// ── Handle Incoming Message ─────────────────────────────────────────

export async function handleIncomingMessage(
  from: string,
  messageBody: string,
): Promise<void> {
  // Check for opt-out keywords first
  if (isOptOutKeyword(messageBody)) {
    await processOptOut(from, messageBody)
    return
  }

  // Check for opt-in / re-subscribe keywords
  const normalizedBody = normalizeMessage(messageBody)
  const OPT_IN_KEYWORDS = ['start', 'unstop', 'resume', 'शुरू', 'మళ్ళీ', 'தொடங்கு']

  if (OPT_IN_KEYWORDS.some((kw) => normalizedBody === normalizeMessage(kw))) {
    await processOptIn(from, messageBody)
    return
  }

  // Normal message — route to bot
  await handleUserQuery(from, messageBody)
}

// ── Process Opt-In (re-subscribe) ───────────────────────────────────

async function processOptIn(from: string, messageBody: string): Promise<void> {
  const normalizedPhone = from.replace(/^\+91/, '').replace(/^\+/, '')

  const user = await db.user.findFirst({
    where: { phone: { contains: normalizedPhone } },
  })

  if (user) {
    const existingConsent = await db.whatsAppConsent.findUnique({
      where: { userId: user.id },
    })

    if (existingConsent) {
      await db.whatsAppConsent.update({
        where: { userId: user.id },
        data: {
          optedIn: true,
          optInAt: new Date(),
          optInMethod: 'whatsapp_start',
          optOutAt: null,
          optOutMethod: null,
          optOutReason: null,
        },
      })
    } else {
      await db.whatsAppConsent.create({
        data: {
          userId: user.id,
          phone: normalizedPhone,
          optedIn: true,
          optInAt: new Date(),
          optInMethod: 'whatsapp_start',
        },
      })
    }

    // Record opt-in analytics
    await db.whatsAppAnalytics.create({
      data: {
        event: 'whatsapp.opt_in.completed',
        userId: user.id,
        metadata: JSON.stringify({
          source: 'whatsapp_start',
          method: 'whatsapp_start',
        }),
      },
    })
  }

  // Send confirmation
  try {
    await whatsappClient.sendTextMessage(
      from,
      "👋 Welcome back! You've been re-subscribed to Daxelo Kinrel WhatsApp notifications. " +
        "Type 'help' to see what I can do!",
    )
  } catch (error) {
    console.error(
      `[WebhookHandler] Failed to send opt-in confirmation to ${from}:`,
      error,
    )
  }

  console.log(
    `[WebhookHandler] Opt-in processed for ${normalizedPhone}`,
  )
}

// ── Handle WhatsAppMessage Object (from webhook) ───────────────────

export async function handleWhatsAppMessage(
  msg: WhatsAppMessage,
): Promise<void> {
  const { from } = msg
  const textBody = msg.text?.body ?? ''
  const buttonReply = (msg.interactive?.button_reply as { title: string } | undefined)?.title
  const listReply = (msg.interactive?.list_reply as { title: string } | undefined)?.title

  // For interactive messages, build the text body from the reply title
  const effectiveBody = textBody || buttonReply || listReply || ''

  if (!effectiveBody) {
    // Non-text message with no interactive reply (e.g., image, document, location)
    await handleNonTextMessage(msg)
    return
  }

  // Process through the opt-out checker
  await handleIncomingMessage(from, effectiveBody)
}

// ── Handle Non-Text Messages ────────────────────────────────────────

async function handleNonTextMessage(msg: WhatsAppMessage): Promise<void> {
  const { from, type } = msg
  const isHindi = false // Default to English for non-text messages

  switch (type) {
    case 'image': {
      const caption = msg.image?.caption ?? ''
      await whatsappClient.sendTextMessage(
        from,
        "📷 Thanks for the image! I can't process images yet, but you can share it in the app. " +
          (caption ? `I see your caption: "${caption}". ` : '') +
          "Type 'help' for available commands.",
      )
      break
    }

    case 'document': {
      const filename = msg.document?.filename ?? 'document'
      await whatsappClient.sendTextMessage(
        from,
        `📄 Thanks for sharing "${filename}". I can't process documents yet, but you can upload it in the app. Type 'help' for available commands.`,
      )
      break
    }

    case 'location': {
      const name = msg.location?.name ?? 'your location'
      await whatsappClient.sendTextMessage(
        from,
        `📍 Thanks for sharing ${name}! Location features coming soon. Type 'help' for available commands.`,
      )
      break
    }

    case 'contacts': {
      await whatsappClient.sendTextMessage(
        from,
        "📇 Thanks for sharing contacts! You can add them to your family tree using 'add [name]'. Type 'help' for all commands.",
      )
      break
    }

    default:
      await whatsappClient.sendTextMessage(
        from,
        "I received your message but can't process this type yet. Type 'help' for available commands.",
      )
  }
}

// ── Verify and Process Webhook Payload ──────────────────────────────

export async function processWebhookPayload(
  payload: {
    object?: string
    entry?: Array<{
      id?: string
      changes?: Array<{
        value?: {
          messages?: Array<Record<string, unknown>>
          statuses?: Array<Record<string, unknown>>
        }
      }>
    }>
  },
): Promise<{ processed: number; errors: number }> {
  let processed = 0
  let errors = 0

  if (payload.object !== 'whatsapp_business_account') {
    return { processed: 0, errors: 0 }
  }

  for (const entry of payload.entry ?? []) {
    for (const change of entry.changes ?? []) {
      // Handle incoming messages
      const messages = change.value?.messages
      if (messages) {
        for (const msg of messages) {
          try {
            const whatsappMsg: WhatsAppMessage = {
              from: (msg.from as string) ?? '',
              messageId: (msg.id as string) ?? '',
              timestamp: (msg.timestamp as string) ?? '',
              type: (msg.type as WhatsAppMessage['type']) ?? 'text',
              text: msg.text as { body: string } | undefined,
              interactive: msg.interactive as WhatsAppMessage['interactive'],
              button: msg.button as WhatsAppMessage['button'],
              document: msg.document as WhatsAppMessage['document'],
              image: msg.image as WhatsAppMessage['image'],
              location: msg.location as WhatsAppMessage['location'],
              contacts: msg.contacts as WhatsAppMessage['contacts'],
            }

            await handleWhatsAppMessage(whatsappMsg)
            processed++
          } catch (error) {
            console.error(
              '[WebhookHandler] Error processing message:',
              error,
            )
            errors++
          }
        }
      }

      // Handle delivery status updates
      const statuses = change.value?.statuses
      if (statuses) {
        const { handleDeliveryStatus } = await import('./delivery-tracking')
        for (const status of statuses) {
          try {
            await handleDeliveryStatus(status as unknown as import('./client').WhatsAppDeliveryStatus)
            processed++
          } catch (error) {
            console.error(
              '[WebhookHandler] Error processing delivery status:',
              error,
            )
            errors++
          }
        }
      }
    }
  }

  return { processed, errors }
}
