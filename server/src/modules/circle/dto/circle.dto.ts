import {
  IsString,
  IsNotEmpty,
  IsOptional,
  IsBoolean,
  IsArray,
  MaxLength,
  ArrayMinSize,
} from 'class-validator';

// ── Circle CRUD DTOs ──────────────────────────────────────────────

export class CreateCircleDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  name: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  description?: string;

  @IsOptional()
  @IsString()
  iconKey?: string;

  @IsOptional()
  @IsBoolean()
  onlyAdminsPost?: boolean;

  @IsOptional()
  @IsBoolean()
  anyoneCanAdd?: boolean;

  // Initial members (userIds) — the creator is auto-added as admin
  @IsOptional()
  @IsArray()
  @ArrayMinSize(0)
  @IsString({ each: true })
  memberUserIds?: string[];
}

export class UpdateCircleDto {
  @IsOptional()
  @IsString()
  @MaxLength(100)
  name?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  description?: string;

  @IsOptional()
  @IsString()
  iconKey?: string;

  @IsOptional()
  @IsString()
  avatarUrl?: string;

  @IsOptional()
  @IsBoolean()
  onlyAdminsPost?: boolean;

  @IsOptional()
  @IsBoolean()
  anyoneCanAdd?: boolean;
}

// ── Member DTOs ──────────────────────────────────────────────────

export class AddMemberDto {
  @IsString()
  @IsNotEmpty()
  userId: string;

  @IsOptional()
  @IsString()
  displayName?: string;

  @IsOptional()
  @IsString()
  avatarUrl?: string;
}

export class MuteDto {
  // null = unmute; a future DateTime = muted until that time
  @IsOptional()
  @IsString()
  mutedUntil?: string | null;
}

// ── Message DTOs ─────────────────────────────────────────────────

export class SendCircleMessageDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(5000)
  content: string;

  @IsOptional()
  @IsString()
  messageType?: string; // text | photo | voiceNote | sticker | gif | document | poll

  @IsOptional()
  @IsString()
  replyToId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(255)
  senderPersonId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(255)
  senderFamilyId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(255)
  senderInitials?: string;

  @IsOptional()
  @IsString()
  mediaUrl?: string;

  @IsOptional()
  @IsString()
  mediaType?: string;

  @IsOptional()
  @IsString()
  mediaFileName?: string;

  // Client-generated optimistic ID — server echoes back on failure
  @IsOptional()
  @IsString()
  @MaxLength(100)
  tempId?: string;
}

export class AddCircleReactionDto {
  @IsString()
  @IsNotEmpty()
  emoji: string;
}

export class MarkCircleReadDto {
  // If omitted, marks ALL unread messages in the circle as read
  @IsOptional()
  @IsString()
  messageId?: string;
}
