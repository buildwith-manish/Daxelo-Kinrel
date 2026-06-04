import { IsString, IsOptional, MaxLength } from 'class-validator';

export class AiChatContextDto {
  @IsOptional()
  @IsString()
  @MaxLength(50)
  familyId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(50)
  personId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(10)
  language?: string;
}

export class AiChatMessageDto {
  @IsOptional()
  @IsString()
  @MaxLength(100)
  sessionId?: string;

  @IsString()
  @MaxLength(2000)
  message!: string;

  @IsOptional()
  context?: AiChatContextDto;
}
