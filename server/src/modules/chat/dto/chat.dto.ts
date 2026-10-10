import { IsString, IsNotEmpty, IsOptional, IsBoolean, MaxLength, IsInt, IsIn, Min } from 'class-validator';

export class SendChatMessageDto {
  @IsString()
  @IsNotEmpty()
  content: string;

  @IsOptional()
  @IsString()
  messageType?: string; // text | photo | voiceNote | sticker | gameInvite | poll ...

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
  senderInitials?: string;

  /// Feature 1: client-generated optimistic ID. The server echoes this
  /// back in the 'chat:messageFailed' event so the client can match the
  /// failure to its local optimistic message + flip status to 'failed'.
  @IsOptional()
  @IsString()
  @MaxLength(100)
  tempId?: string;

  /// Tier 1 Feature 1.4: silent send. When true, FCM push for this
  /// message is delivered at low priority with no sound + no vibration.
  @IsOptional()
  @IsBoolean()
  silent?: boolean;

  /// Tier 1 Feature 1.14: caption for media messages (photo / video /
  /// document / gif). Renders below the media inside the bubble.
  @IsOptional()
  @IsString()
  @MaxLength(4096)
  caption?: string;

  /// Tier 1 Feature 1.5: view-once media. When true, the underlying media
  /// is deleted 24h after the first view.
  @IsOptional()
  @IsBoolean()
  isViewOnce?: boolean;

  /// Tier 1 Feature 1.6: photo quality tier — 'standard' or 'hd'.
  @IsOptional()
  @IsString()
  @IsIn(['standard', 'hd'])
  qualityTier?: string;

  /// Tier 1 Feature 1.11: document display name (PDF/DOCX/etc.).
  @IsOptional()
  @IsString()
  @MaxLength(255)
  documentName?: string;

  /// Tier 1 Feature 1.11: document page count (for PDFs).
  @IsOptional()
  @IsInt()
  @Min(0)
  documentPages?: number;

  /// Tier 2 Feature 2.7: anonymous admin — only admins/creators can use.
  /// The server silently downgrades to false if a non-admin passes it.
  @IsOptional()
  @IsBoolean()
  isAnonymousAdmin?: boolean;

  /// Tier 2 Feature 2.5: forum topic ID — null = General topic.
  @IsOptional()
  @IsString()
  @MaxLength(100)
  topicId?: string;
}

export class MarkAsReadDto {
  // messageId can be omitted to mark ALL unread messages in the family as read
  @IsOptional()
  @IsString()
  messageId?: string;
}

export class AddReactionDto {
  @IsString()
  @IsNotEmpty()
  messageId: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(32) // emoji + ZWJ sequences are short, but cap to be safe
  emoji: string;
}

export class RemoveReactionDto {
  @IsString()
  @IsNotEmpty()
  messageId: string;

  @IsString()
  @IsNotEmpty()
  emoji: string;
}

export class TypingDto {
  @IsString()
  @IsNotEmpty()
  familyId: string;

  @IsBoolean()
  isTyping: boolean;

  @IsOptional()
  @IsString()
  userName?: string;
}
