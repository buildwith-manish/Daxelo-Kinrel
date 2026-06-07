import { IsOptional, IsString, MaxLength } from 'class-validator';

export class AiChatMessageDto {
  @IsOptional()
  @IsString()
  sessionId?: string;

  @IsString()
  @MaxLength(2000)
  message!: string;
}
