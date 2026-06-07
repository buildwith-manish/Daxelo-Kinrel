import { IsString, IsNotEmpty, IsBoolean, IsOptional, IsInt, IsIn, Min, Max, MaxLength } from 'class-validator';
import { Type } from 'class-transformer';

export class UpdatePreferenceDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  eventType!: string;

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
  @IsBoolean()
  whatsapp?: boolean;

  @IsOptional()
  @IsString()
  @MaxLength(5)
  quietHoursStart?: string;

  @IsOptional()
  @IsString()
  @MaxLength(5)
  quietHoursEnd?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  maxPerDay?: number;

  @IsOptional()
  @IsIn(['instant', 'hourly', 'daily', 'weekly'])
  digestMode?: string;
}
