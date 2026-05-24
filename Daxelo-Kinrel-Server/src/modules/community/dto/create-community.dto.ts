import { IsString, IsOptional, IsEnum, IsBoolean } from 'class-validator';

export class CreateCommunityDto {
  @IsEnum(['gotra', 'village', 'surname', 'custom'])
  type!: string;

  @IsString()
  name!: string;

  @IsOptional()
  @IsString()
  description?: string;

  @IsOptional()
  @IsString()
  coverImageUrl?: string;

  @IsOptional()
  @IsString()
  iconUrl?: string;

  @IsOptional()
  @IsBoolean()
  isPrivate?: boolean;

  @IsOptional()
  @IsString()
  gotraName?: string;

  @IsOptional()
  @IsString()
  villageName?: string;

  @IsOptional()
  @IsString()
  surname?: string;

  @IsOptional()
  @IsString()
  region?: string;

  @IsString()
  creatorId!: string;
}
