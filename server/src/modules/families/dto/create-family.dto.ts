import { IsString, IsOptional, IsNotEmpty, IsIn } from 'class-validator';

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
}
