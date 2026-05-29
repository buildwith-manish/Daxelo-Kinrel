import { IsString, IsOptional } from 'class-validator';

export class AiChatContextDto {
  @IsOptional()
  @IsString()
  familyId?: string;

  @IsOptional()
  @IsString()
  personId?: string;

  @IsOptional()
  @IsString()
  language?: string;
}

export class AiChatMessageDto {
  @IsOptional()
  @IsString()
  sessionId?: string;

  @IsString()
  message!: string;

  @IsOptional()
  context?: AiChatContextDto;
}
