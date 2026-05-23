// DAXELO KINREL — WhatsApp Webhook Handler
// Pack 04: WhatsApp Platform — API Route

import { NextRequest, NextResponse } from 'next/server'
import { whatsappClient, WhatsAppMessage, WhatsAppDeliveryStatus } from '@/lib/whatsapp/client'
import { routeCommand } from '@/lib/whatsapp/bot-router'
import { handleDeliveryStatus } from '@/lib/whatsapp/delivery-tracking'

// ── GET: Webhook Verification ────────────────────────────────────
// WhatsApp Business API sends this during initial webhook setup.
// Must verify hub.mode=subscribe and hub.verify_token, then return hub.challenge.

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url)
    const mode = searchParams.get('hub.mode')
    const token = searchParams.get('hub.verify_token')
    const challenge = searchParams.get('hub.challenge')

    if (mode && token && whatsappClient.verifyWebhookToken(mode, token)) {
      // Verification successful — return the challenge string
      return new NextResponse(challenge ?? '', { status: 200 })
    }

    return NextResponse.json(
      { error: 'Invalid verification token or mode' },
      { status: 403 },
    )
  } catch (error) {
    console.error('[WhatsApp Webhook GET] Error during verification:', error)
    return NextResponse.json(
      { error: 'Webhook verification failed' },
      { status: 500 },
    )
  }
}

// ── POST: Incoming Message Handler ───────────────────────────────
// Receives incoming WhatsApp messages and delivery status updates.

export async function POST(request: NextRequest) {
  try {
    // Read raw body as text for signature verification
    const rawBody = await request.text()

    // Verify signature from x-hub-signature-256 header
    const signature = request.headers.get('x-hub-signature-256') ?? ''

    if (!whatsappClient.verifyWebhookSignature(rawBody, signature)) {
      return NextResponse.json(
        { error: 'Invalid webhook signature' },
        { status: 401 },
      )
    }

    // Parse JSON payload
    const payload = JSON.parse(rawBody)

    // Process only WhatsApp Business Account events
    if (payload.object === 'whatsapp_business_account') {
      const entries = payload.entry ?? []

      for (const entry of entries) {
        const changes = entry.changes ?? []

        for (const change of changes) {
          // Handle incoming messages
          const messages = change.value?.messages
          if (messages && Array.isArray(messages)) {
            for (const msg of messages) {
              try {
                await routeCommand(msg as WhatsAppMessage)
              } catch (error) {
                console.error(
                  '[WhatsApp Webhook POST] Bot handler error for message:',
                  msg.messageId,
                  error,
                )
                // Send fallback error message to user
                try {
                  await whatsappClient.sendTextMessage(
                    msg.from,
                    "I couldn't process that. Type 'help' for available commands.",
                  )
                } catch (sendError) {
                  console.error(
                    '[WhatsApp Webhook POST] Failed to send fallback message:',
                    sendError,
                  )
                }
              }
            }
          }

          // Handle delivery status updates
          const statuses = change.value?.statuses
          if (statuses && Array.isArray(statuses)) {
            for (const status of statuses) {
              try {
                await handleDeliveryStatus(status as WhatsAppDeliveryStatus)
              } catch (error) {
                console.error(
                  '[WhatsApp Webhook POST] Delivery status handler error:',
                  error,
                )
              }
            }
          }
        }
      }
    }

    // Always return 200 quickly — WhatsApp expects fast acknowledgment
    return NextResponse.json({ status: 'ok' }, { status: 200 })
  } catch (error) {
    console.error('[WhatsApp Webhook POST] Unhandled error:', error)
    // Still return 200 to prevent WhatsApp from retrying
    return NextResponse.json({ status: 'ok' }, { status: 200 })
  }
}
