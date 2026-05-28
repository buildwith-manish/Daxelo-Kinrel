import { IsString, IsOptional, IsEnum, IsBoolean, IsInt, MaxLength } from 'class-validator';

export class UpdateFamilyDto {
  @IsString()
  @IsOptional()
  @MaxLength(100)
  name?: string;

  @IsString()
  @IsOptional()
  @MaxLength(50)
  username?: string;

  @IsString()
  @IsOptional()
  avatarUrl?: string;

  @IsString()
  @IsOptional()
  region?: string;

  @IsEnum(['public', 'private', 'invite-only'])
  @IsOptional()
  privacyMode?: string;

  @IsBoolean()
  @IsOptional()
  isOnboarded?: boolean;

  @IsString()
  @IsOptional()
  anchorPersonId?: string;

  @IsInt()
  @IsOptional()
  memberCount?: number;

  @IsInt()
  @IsOptional()
  generationCount?: number;

  @IsString()
  @IsOptional()
  @MaxLength(500)
  description?: string;

  @IsString()
  @IsOptional()
  primaryLanguage?: string;

  @IsString()
  @IsOptional()
  gotra?: string;

  @IsString()
  @IsOptional()
  originVillage?: string;
}
