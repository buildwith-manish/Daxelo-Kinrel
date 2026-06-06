import { IsEnum, IsOptional, IsString, MaxLength } from 'class-validator';

export enum SparqTypeDto {
  IMAGE = 'IMAGE',
  VIDEO = 'VIDEO',
  TEXT = 'TEXT',
  VOICE = 'VOICE',
}

export enum SparqAudienceDto {
  PUBLIC = 'PUBLIC',
  FAMILY_ONLY = 'FAMILY_ONLY',
}

export class CreateSparqDto {
  @IsEnum(SparqTypeDto)
  type!: string;

  @IsEnum(SparqAudienceDto)
  @IsOptional()
  audience?: string = 'PUBLIC';

  @IsOptional()
  @IsString()
  @MaxLength(500)
  text?: string;

  @IsOptional()
  @IsString()
  @MaxLength(20)
  bgColor?: string;
}
