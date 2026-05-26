import { IsString, IsOptional, Length, IsIn } from 'class-validator';

const VALID_TARGET_TYPES = ['post', 'comment', 'community', 'user'] as const;
const VALID_REASONS = [
  'spam', 'harassment', 'hate_speech', 'caste_reference',
  'misinformation', 'sexual_content', 'violence',
  'impersonation', 'pii_exposure', 'other',
] as const;

export class ReportContentDto {
  @IsString()
  reporterId!: string;

  @IsString()
  @IsIn(VALID_TARGET_TYPES)
  targetType!: string;

  @IsString()
  targetId!: string;

  @IsString()
  @IsIn(VALID_REASONS)
  reason!: string;

  @IsOptional()
  @IsString()
  @Length(0, 2000)
  description?: string;
}
