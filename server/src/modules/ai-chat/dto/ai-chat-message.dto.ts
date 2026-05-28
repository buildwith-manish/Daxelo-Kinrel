import { IsOptional, IsString } from 'class-validator';

export class AiChatMessageDto {
  @IsOptional()
  @IsString()
  sessionId?: string;

  @IsString()
  message!: string;
}
