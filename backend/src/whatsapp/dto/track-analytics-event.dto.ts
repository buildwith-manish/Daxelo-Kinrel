import { IsString, IsOptional, IsObject } from 'class-validator';

export class TrackAnalyticsEventDto {
  @IsString()
  event!: string;

  @IsOptional()
  @IsString()
  userId?: string;

  @IsOptional()
  @IsString()
  familyId?: string;

  @IsOptional()
  @IsString()
  messageId?: string;

  @IsOptional()
  @IsString()
  templateId?: string;

  @IsOptional()
  @IsObject()
  metadata?: Record<string, unknown>;
}
