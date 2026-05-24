import { IsString, IsOptional, IsEnum, IsInt, Min, Max } from 'class-validator';

/**
 * DTO for PUT /api/notifications — Update notification preferences
 */
export class UpdatePreferenceDto {
  @IsString()
  userId!: string;

  @IsString()
  eventType!: string;

  @IsOptional()
  @IsString()
  whatsapp?: boolean;

  @IsOptional()
  @IsString()
  push?: boolean;

  @IsOptional()
  @IsString()
  inApp?: boolean;

  @IsOptional()
  @IsString()
  email?: boolean;

  @IsOptional()
  @IsString()
  quietHoursStart?: string;

  @IsOptional()
  @IsString()
  quietHoursEnd?: string;

  @IsOptional()
  @IsEnum(['immediate', 'hourly', 'daily'])
  digestMode?: 'immediate' | 'hourly' | 'daily';

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(100)
  maxPerDay?: number;
}
