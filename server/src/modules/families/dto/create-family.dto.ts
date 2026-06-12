import { IsString, IsOptional, IsNotEmpty, IsIn, IsUrl } from 'class-validator';

export class CreateFamilyDto {
  @IsString()
  @IsNotEmpty()
  name!: string;

  @IsOptional()
  @IsString()
  description?: string;

  @IsOptional()
  @IsString()
  primaryLanguage?: string;

  @IsOptional()
  @IsString()
  gotra?: string;

  @IsOptional()
  @IsString()
  originVillage?: string;

  @IsOptional()
  @IsIn(['private', 'invite', 'link'])
  privacyMode?: string;

  @IsOptional()
  @IsString()
  region?: string;

  @IsOptional()
  @IsString()
  username?: string;

  @IsOptional()
  @IsString()
  avatarUrl?: string;
}
