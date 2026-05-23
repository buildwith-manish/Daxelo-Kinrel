import crypto from 'crypto'
import { db } from '@/lib/db'

// ── Event Types ──────────────────────────────────────────────────────

export const EVENT_TYPES = {
  'person.created': {
    description: 'A new person was added to a family',
    payloadSchema: { personId: 'string', familyId: 'string', name: 'string' },
  },
  'person.updated': {
    description: 'A person record was updated',
    payloadSchema: { personId: 'string', familyId: 'string', changedFields: 'string[]' },
  },
  'person.deleted': {
    description: 'A person was removed from a family',
    payloadSchema: { personId: 'string', familyId: 'string' },
  },
  'relationship.created': {
    description: 'A new relationship was established',
    payloadSchema: { relationshipId: 'string', familyId: 'string', fromPersonId: 'string', toPersonId: 'string', type: 'string' },
  },
  'relationship.updated': {
    description: 'A relationship was updated',
    payloadSchema: { relationshipId: 'string', familyId: 'string', type: 'string' },
  },
  'relationship.deleted': {
    description: 'A relationship was removed',
    payloadSchema: { relationshipId: 'string', familyId: 'string' },
  },
  'family.created': {
    description: 'A new family was created',
    payloadSchema: { familyId: 'string', name: 'string' },
  },
  'family.updated': {
    description: 'A family record was updated',
    payloadSchema: { familyId: 'string', changedFields: 'string[]' },
  },
  'family.deleted': {
    description: 'A family was deleted',
    payloadSchema: { familyId: 'string' },
  },
  'family.member_added': {
    description: 'A user joined a family',
    payloadSchema: { familyId: 'string', userId: 'string', role: 'string' },
  },
  'family.member_removed': {
    description: 'A user left or was removed from a family',
    payloadSchema: { familyId: 'string', userId: 'string' },
  },
  'family.member_role_changed': {
    description: 'A family member role was changed',
    payloadSchema: { familyId: 'string', userId: 'string', oldRole: 'string', newRole: 'string' },
  },
  'invitation.accepted': {
    description: 'A family invitation was accepted',
    payloadSchema: { invitationId: 'string', familyId: 'string', userId: 'string' },
  },
  'birthday.upcoming': {
    description: 'A birthday is approaching',
    payloadSchema: { personId: 'string', familyId: 'string', name: 'string', date: 'string' },
  },
} as const

export type WebhookEventType = keyof typeof EVENT_TYPES

// ── Retry Schedule (in seconds) ──────────────────────────────────────

const RETRY_SCHEDULE = [0, 60, 300, 900, 3600]

// ── Sign Webhook ─────────────────────────────────────────────────────

export function signWebhook(payload: string, secret: string): string {
  return crypto.createHmac('sha256', secret).update(payload).digest('hex')
}

// ── Verify Webhook Signature ─────────────────────────────────────────

export function verifyWebhookSignature(
  payload: string,
  signature: string,
  secret: string
): boolean {
  const expected = signWebhook(payload, secret)

  // Timing-safe comparison
  if (signature.length !== expected.length) {
    return false
  }

  let result = 0
  for (let i = 0; i < signature.length; i++) {
    result |= signature.charCodeAt(i) ^ expected.charCodeAt(i)
  }
  return result === 0
}

// ── Emit Webhook Event ──────────────────────────────────────────────

export async function emit(
  eventType: string,
  data: object,
  familyId?: string
): Promise<void> {
  // Find matching subscriptions
  const subscriptions = await db.webhookSubscription.findMany({
    where: {
      active: true,
      events: { contains: eventType },
    },
  })

  // Filter by familyId if specified (or global subscriptions)
  const matchingSubs = familyId
    ? subscriptions
    : subscriptions

  const payload = JSON.stringify({
    event: eventType,
    data,
    familyId: familyId || null,
    timestamp: new Date().toISOString(),
  })

  for (const sub of matchingSubs) {
    const events: string[] = JSON.parse(sub.events)
    if (!events.includes(eventType) && !events.includes('*')) {
      continue
    }

    const signature = signWebhook(payload, sub.secret)
    const now = new Date()

    await db.webhookDelivery.create({
      data: {
        webhookId: sub.id,
        eventId: `evt_${crypto.randomBytes(12).toString('hex')}`,
        eventType,
        payload,
        signature,
        attemptCount: 0,
        maxAttempts: 5,
        status: 'pending',
        nextAttemptAt: now,
      },
    })
  }
}

// ── Process Pending Deliveries ───────────────────────────────────────

export async function processPending(): Promise<number> {
  const now = new Date()

  const pending = await db.webhookDelivery.findMany({
    where: {
      status: 'pending',
      nextAttemptAt: { lte: now },
      attemptCount: { lt: 5 },
    },
    include: {
      webhook: true,
    },
    take: 50,
  })

  let processed = 0

  for (const delivery of pending) {
    try {
      const webhook = delivery.webhook
      if (!webhook || !webhook.active) {
        await db.webhookDelivery.update({
          where: { id: delivery.id },
          data: { status: 'ignored' },
        })
        continue
      }

      // Attempt delivery
      const response = await fetch(webhook.url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Kinrel-Signature': `sha256=${delivery.signature}`,
          'X-Kinrel-Event': delivery.eventType,
          'X-Kinrel-Delivery': delivery.eventId,
        },
        body: delivery.payload,
        signal: AbortSignal.timeout(10_000), // 10s timeout
      })

      const newAttemptCount = delivery.attemptCount + 1

      if (response.ok) {
        await db.webhookDelivery.update({
          where: { id: delivery.id },
          data: {
            status: 'delivered',
            attemptCount: newAttemptCount,
            lastAttemptAt: now,
            responseStatusCode: response.status,
            responseBody: await response.text().catch(() => null),
          },
        })
        processed++
      } else {
        // Failed, schedule retry
        const nextRetryDelay = RETRY_SCHEDULE[Math.min(newAttemptCount, RETRY_SCHEDULE.length - 1)] ?? 3600
        const nextAttempt = new Date(now.getTime() + nextRetryDelay * 1000)

        const isFinalAttempt = newAttemptCount >= delivery.maxAttempts

        await db.webhookDelivery.update({
          where: { id: delivery.id },
          data: {
            status: isFinalAttempt ? 'failed' : 'pending',
            attemptCount: newAttemptCount,
            lastAttemptAt: now,
            nextAttemptAt: isFinalAttempt ? undefined : nextAttempt,
            responseStatusCode: response.status,
            responseBody: await response.text().catch(() => null),
          },
        })
        processed++
      }
    } catch {
      // Network error, schedule retry
      const newAttemptCount = delivery.attemptCount + 1
      const nextRetryDelay = RETRY_SCHEDULE[Math.min(newAttemptCount, RETRY_SCHEDULE.length - 1)] ?? 3600
      const nextAttempt = new Date(now.getTime() + nextRetryDelay * 1000)
      const isFinalAttempt = newAttemptCount >= delivery.maxAttempts

      await db.webhookDelivery.update({
        where: { id: delivery.id },
        data: {
          status: isFinalAttempt ? 'failed' : 'pending',
          attemptCount: newAttemptCount,
          lastAttemptAt: now,
          nextAttemptAt: isFinalAttempt ? undefined : nextAttempt,
        },
      })
      processed++
    }
  }

  return processed
}

// ── Create Webhook Subscription ──────────────────────────────────────

export async function createWebhookSubscription(
  userId: string,
  url: string,
  events: string[],
  secret?: string
) {
  const webhookSecret = secret || crypto.randomBytes(32).toString('hex')

  return db.webhookSubscription.create({
    data: {
      userId,
      url,
      secret: webhookSecret,
      events: JSON.stringify(events),
      active: true,
    },
  })
}

// ── Test Webhook ─────────────────────────────────────────────────────

export async function testWebhook(subscriptionId: string) {
  const subscription = await db.webhookSubscription.findUnique({
    where: { id: subscriptionId },
  })

  if (!subscription) {
    throw new Error('Webhook subscription not found')
  }

  const testPayload = JSON.stringify({
    event: 'test',
    data: { message: 'Test webhook from KINREL API' },
    timestamp: new Date().toISOString(),
  })

  const signature = signWebhook(testPayload, subscription.secret)
  const now = new Date()

  const delivery = await db.webhookDelivery.create({
    data: {
      webhookId: subscription.id,
      eventId: `evt_test_${crypto.randomBytes(8).toString('hex')}`,
      eventType: 'test',
      payload: testPayload,
      signature,
      attemptCount: 0,
      maxAttempts: 1,
      status: 'pending',
      nextAttemptAt: now,
    },
  })

  // Attempt delivery immediately
  try {
    const response = await fetch(subscription.url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Kinrel-Signature': `sha256=${signature}`,
        'X-Kinrel-Event': 'test',
        'X-Kinrel-Delivery': delivery.eventId,
      },
      body: testPayload,
      signal: AbortSignal.timeout(10_000),
    })

    const responseBody = await response.text().catch(() => null)

    await db.webhookDelivery.update({
      where: { id: delivery.id },
      data: {
        status: response.ok ? 'delivered' : 'failed',
        attemptCount: 1,
        lastAttemptAt: new Date(),
        responseStatusCode: response.status,
        responseBody,
      },
    })

    return db.webhookDelivery.findUnique({ where: { id: delivery.id } })
  } catch {
    await db.webhookDelivery.update({
      where: { id: delivery.id },
      data: {
        status: 'failed',
        attemptCount: 1,
        lastAttemptAt: new Date(),
      },
    })

    return db.webhookDelivery.findUnique({ where: { id: delivery.id } })
  }
}
