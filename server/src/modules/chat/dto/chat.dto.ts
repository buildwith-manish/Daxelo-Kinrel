import { IsString, IsNotEmpty, IsOptional, IsBoolean, MaxLength } from 'class-validator';

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
