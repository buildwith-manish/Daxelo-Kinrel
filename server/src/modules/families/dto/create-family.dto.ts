import { IsString, IsOptional, IsNotEmpty, IsIn, MaxLength } from 'class-validator';

export class CreateFamilyDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  name!: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  description?: string;

  @IsOptional()
  @IsString()
  @MaxLength(30)
  primaryLanguage?: string;

  @IsOptional()
  @IsString()
  @MaxLength(50)
  gotra?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  originVillage?: string;

  @IsOptional()
  @IsIn(['private', 'invite', 'link'])
  privacyMode?: string;
}
