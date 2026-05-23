import { IsString, IsOptional, IsEnum } from 'class-validator';

const VALID_TARGET_TYPES = ['post', 'comment', 'community', 'user'] as const;
const VALID_REASONS = [
  'spam', 'harassment', 'hate_speech', 'caste_reference',
  'misinformation', 'sexual_content', 'violence', 'impersonation',
  'pii_exposure', 'other',
] as const;

export class ReportDto {
  @IsString()
  reporterId!: string;

  @IsEnum(VALID_TARGET_TYPES)
  targetType!: string;

  @IsString()
  targetId!: string;

  @IsEnum(VALID_REASONS)
  reason!: string;

  @IsOptional()
  @IsString()
  description?: string;
}
