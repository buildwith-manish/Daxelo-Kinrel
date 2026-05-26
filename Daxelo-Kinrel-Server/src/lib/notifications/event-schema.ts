// DAXELO KINREL — Notification Event Schema
// Pack 04: WhatsApp Platform — Notification Pipeline

/**
 * Notification event types covering family, person, relationship,
 * subscription, AI, system, and community events.
 */
export type NotificationEventType =
  | 'family.member_added'
  | 'family.member_removed'
  | 'family.invitation_sent'
  | 'family.invitation_accepted'
  | 'family.role_changed'
  | 'person.birthday_upcoming'
  | 'person.anniversary_upcoming'
  | 'person.deceased_memorial'
  | 'person.health_alert'
  | 'relationship.added'
  | 'relationship.suggested'
  | 'subscription.payment_failed'
  | 'subscription.trial_ending'
  | 'subscription.renewed'
  | 'ai.suggestion_ready'
  | 'system.maintenance'
  | 'community.mention'
  | 'community.comment';

/**
 * Priority levels for notification events.
 * - critical: Requires immediate attention, bypasses quiet hours and all opt-in checks
 * - high: Important but not urgent, respects quiet hours
 * - normal: Standard priority, respects all user preferences
 * - low: Informational, can be batched into digest
 */
export type NotificationPriority = 'critical' | 'high' | 'normal' | 'low';

/**
 * Core notification event interface that flows through the notification engine.
 * Every event must have a dedupKey for 24-hour deduplication.
 */
export interface NotificationEvent {
  /** Unique identifier for this event (UUID v7 recommended for time-ordering) */
  id: string;

  /** The type of notification event */
  type: NotificationEventType;

  /** ID of the user who triggered the event */
  actorUserId: string;

  /** ID of the user who should receive the notification */
  targetUserId: string;

  /** Optional family ID to scope the notification */
  familyId?: string;

  /** Optional person ID to scope the notification */
  personId?: string;

  /** Additional data specific to the event type */
  payload: Record<string, unknown>;

  /** Priority level determining delivery behavior */
  priority: NotificationPriority;

  /** Timestamp when the event was created */
  createdAt: Date;

  /**
   * Deduplication key for 24-hour window.
   * Should combine event type + target + relevant entity IDs
   * e.g., "person.birthday_upcoming:uid123:pid456"
   */
  dedupKey: string;
}

/**
 * Resolved notification template with title and body text.
 */
export interface NotificationTemplate {
  title: string;
  body: string;
}

/**
 * Channel names supported by the notification engine.
 */
export type NotificationChannel = 'whatsapp' | 'push' | 'inApp' | 'email';

/**
 * Delivery status for a notification per channel.
 */
export type NotificationDeliveryStatus = 'pending' | 'delivered' | 'failed' | 'read';

/**
 * Result of processing a notification event through the engine.
 */
export interface NotificationProcessResult {
  notificationId: string;
  channels: NotificationChannel[];
  delivered: NotificationChannel[];
  failed: Array<{ channel: NotificationChannel; error: string }>;
  deduplicated: boolean;
  rateLimited: boolean;
}

/**
 * Mapping of event types to their category groups.
 * Used for preference management and analytics.
 */
export const EVENT_TYPE_CATEGORIES: Record<NotificationEventType, string> = {
  'family.member_added': 'family',
  'family.member_removed': 'family',
  'family.invitation_sent': 'family',
  'family.invitation_accepted': 'family',
  'family.role_changed': 'family',
  'person.birthday_upcoming': 'person',
  'person.anniversary_upcoming': 'person',
  'person.deceased_memorial': 'person',
  'person.health_alert': 'person',
  'relationship.added': 'relationship',
  'relationship.suggested': 'relationship',
  'subscription.payment_failed': 'subscription',
  'subscription.trial_ending': 'subscription',
  'subscription.renewed': 'subscription',
  'ai.suggestion_ready': 'ai',
  'system.maintenance': 'system',
  'community.mention': 'community',
  'community.comment': 'community',
};

/**
 * Default priority mapping for event types.
 * Used when no explicit priority is provided.
 */
export const DEFAULT_EVENT_PRIORITIES: Record<NotificationEventType, NotificationPriority> = {
  'family.member_added': 'normal',
  'family.member_removed': 'high',
  'family.invitation_sent': 'normal',
  'family.invitation_accepted': 'normal',
  'family.role_changed': 'normal',
  'person.birthday_upcoming': 'normal',
  'person.anniversary_upcoming': 'normal',
  'person.deceased_memorial': 'high',
  'person.health_alert': 'critical',
  'relationship.added': 'normal',
  'relationship.suggested': 'low',
  'subscription.payment_failed': 'critical',
  'subscription.trial_ending': 'high',
  'subscription.renewed': 'normal',
  'ai.suggestion_ready': 'low',
  'system.maintenance': 'high',
  'community.mention': 'normal',
  'community.comment': 'normal',
};
