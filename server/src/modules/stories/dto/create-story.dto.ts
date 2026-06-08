import { IsString, IsOptional, IsDateString, IsIn, IsUrl, MaxLength } from 'class-validator';

export class CreateStoryDto {
  @IsOptional()
  @IsString()
  familyId?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  caption?: string;

  @IsOptional()
  @IsUrl()
  @MaxLength(2048)
  mediaUrl?: string;

  @IsOptional()
  @IsIn(['text', 'image', 'video'])
  mediaType?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  bgGradient?: string;

  @IsDateString()
  expiresAt!: string;
}
