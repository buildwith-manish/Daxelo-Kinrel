import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsString, IsOptional, IsIn } from 'class-validator';

export class CreateStoryDto {
  @ApiPropertyOptional({ description: 'Family ID to associate the story with' })
  @IsOptional()
  @IsString()
  familyId?: string;

  @ApiPropertyOptional({ description: 'Caption text for the story' })
  @IsOptional()
  @IsString()
  caption?: string;

  @ApiPropertyOptional({ description: 'Media type', enum: ['text', 'image', 'video'], default: 'text' })
  @IsOptional()
  @IsIn(['text', 'image', 'video'])
  mediaType?: string;

  @ApiPropertyOptional({ description: 'Tailwind gradient class for text stories' })
  @IsOptional()
  @IsString()
  bgGradient?: string;

  @ApiPropertyOptional({
    description: 'Audience scope for the story',
    enum: ['PUBLIC', 'FAMILY_ONLY'],
    default: 'PUBLIC',
  })
  @IsOptional()
  @IsIn(['PUBLIC', 'FAMILY_ONLY'])
  audience?: string;
}
