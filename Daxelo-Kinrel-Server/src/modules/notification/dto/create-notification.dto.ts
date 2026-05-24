import {
  IsString,
  IsOptional,
  IsEnum,
  IsArray,
  IsObject,
  ValidateNested,
  IsBoolean,
} from 'class-validator';
import { Type } from 'class-transformer';

/**
 * Valid notification priorities
 */
export const NOTIFICATION_PRIORITIES = [
  'critical',
  'high',
  'normal',
  'low',
] as const;

export type NotificationPriority = (typeof NOTIFICATION_PRIORITIES)[number];

/**
 * Valid notification event types
 */
export const NOTIFICATION_EVENT_TYPES = [
  'family.member_added',
  'family.member_removed',
  'family.invitation_sent',
  'family.invitation_accepted',
  'family.role_changed',
  'person.birthday_upcoming',
  'person.anniversary_upcoming',
  'person.deceased_memorial',
  'person.health_alert',
  'relationship.added',
  'relationship.suggested',
  'subscription.payment_failed',
  'subscription.trial_ending',
  'subscription.renewed',
  'ai.suggestion_ready',
  'system.maintenance',
  'community.mention',
  'community.comment',
  'community.festival_greeting',
] as const;

export type NotificationEventType =
  (typeof NOTIFICATION_EVENT_TYPES)[number];

/**
 * DTO for POST /api/notifications — Create notification
 */
export class CreateNotificationDto {
  @IsString()
  type!: NotificationEventType;

  @IsString()
  actorUserId!: string;

  @IsString()
  targetUserId!: string;

  @IsOptional()
  @IsString()
  familyId?: string;

  @IsOptional()
  @IsString()
  personId?: string;

  @IsObject()
  payload!: Record<string, unknown>;

  @IsEnum(NOTIFICATION_PRIORITIES)
  priority!: NotificationPriority;
}
