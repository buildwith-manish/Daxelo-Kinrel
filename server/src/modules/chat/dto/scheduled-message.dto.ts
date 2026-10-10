// server/src/modules/chat/dto/scheduled-message.dto.ts
//
// DAXELO KINREL — Tier 1 Feature 1.2: Scheduled Messages
//
// DTOs for the schedule/cancel/list endpoints exposed by
// ScheduledMessagesController. The actual dispatch is in
// ScheduledMessagesService, which calls the existing fn_send_scheduled_messages
// RPC via the Prisma raw query interface.

import {
  IsString,
  IsNotEmpty,
  IsOptional,
  IsDateString,
  IsIn,
  MaxLength,
  ValidateIf,
} from 'class-validator';

export class ScheduleMessageDto {
  // Exactly one of familyId / receiverId must be set. The controller
  // enforces this with a manual check since class-validator's @ValidateIf
  // is awkward for "exactly-one-of" rules.
  @IsOptional()
  @IsString()
  @MaxLength(100)
  familyId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  receiverId?: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(4096)
  content: string;

  // ISO 8601 timestamp. Must be at least 1 minute in the future.
  @IsDateString()
  scheduledFor: string;

  @IsOptional()
  @IsString()
  @IsIn(['text', 'photo', 'voiceNote', 'sticker', 'gif', 'document', 'location'])
  messageType?: string;

  @IsOptional()
  @IsString()
  @MaxLength(2048)
  mediaUrl?: string;

  @IsOptional()
  @IsString()
  @MaxLength(64)
  mediaType?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  replyToId?: string;

  /// Optional client-generated idempotency key. If provided AND a
  /// ScheduledMessage with this ID already exists, the server returns
  /// the existing row instead of creating a duplicate. Matches the
  /// pattern used by ChatService.sendMessage for retry-after-reconnect.
  @IsOptional()
  @IsString()
  @MaxLength(120)
  clientScheduleId?: string;

  /// Force-validate that EXACTLY one of familyId / receiverId is set.
  /// class-validator's @ValidateIf doesn't express "exactly-one-of"
  /// cleanly, so we use a class-level validator on the controller instead.
  @ValidateIf((o) => !o.familyId && !o.receiverId)
  @IsString()
  @IsNotEmpty()
  _atLeastOneTargetRequired?: string;
}
