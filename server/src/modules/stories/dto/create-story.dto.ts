import { IsString, IsOptional, IsDateString, IsIn } from 'class-validator';

export class CreateStoryDto {
  @IsOptional()
  @IsString()
  familyId?: string;

  @IsOptional()
  @IsString()
  caption?: string;

  @IsOptional()
  @IsString()
  mediaUrl?: string;

  @IsOptional()
  @IsIn(['text', 'image', 'video'])
  mediaType?: string;

  @IsOptional()
  @IsString()
  bgGradient?: string;

  @IsDateString()
  expiresAt!: string;
}
