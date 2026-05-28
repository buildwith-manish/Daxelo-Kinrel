import { IsString, IsOptional, IsEnum, IsNotEmpty, MaxLength } from 'class-validator';

export class CreateFamilyDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  name!: string;

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
