import { IsString, IsOptional, IsBoolean, IsInt, IsIn, Min, Max } from 'class-validator';

export class UpdatePreferencesDto {
  @IsString()
  userId!: string;

  @IsString()
  eventType!: string;

  @IsOptional()
  @IsBoolean()
  whatsapp?: boolean;

  @IsOptional()
  @IsBoolean()
  push?: boolean;

  @IsOptional()
  @IsBoolean()
  inApp?: boolean;

  @IsOptional()
  @IsBoolean()
  email?: boolean;

  @IsOptional()
  @IsString()
  quietHoursStart?: string;

  @IsOptional()
  @IsString()
  quietHoursEnd?: string;

  @IsOptional()
  @IsIn(['immediate', 'hourly', 'daily'])
  digestMode?: 'immediate' | 'hourly' | 'daily';

  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(100)
  maxPerDay?: number;
}
