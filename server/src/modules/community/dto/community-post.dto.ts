import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsString,
  IsOptional,
  IsNotEmpty,
  IsIn,
  IsArray,
  IsBoolean,
} from 'class-validator';

export class CreateCommunityPostDto {
  @ApiProperty({
    description: 'Post type',
    enum: ['discussion', 'announcement', 'poll', 'media'],
  })
  @IsString()
  @IsNotEmpty()
  @IsIn(['discussion', 'announcement', 'poll', 'media'])
  type!: string;

  @ApiPropertyOptional({ description: 'Post title' })
  @IsOptional()
  @IsString()
  title?: string;

  @ApiProperty({ description: 'Post body content' })
  @IsString()
  @IsNotEmpty()
  body!: string;

  @ApiPropertyOptional({ description: 'Media URLs', type: [String] })
  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  mediaUrls?: string[];

  @ApiProperty({
    description: 'Post visibility',
    enum: ['public', 'members_only'],
    default: 'members_only',
  })
  @IsString()
  @IsIn(['public', 'members_only'])
  visibility!: string;
}

export class UpdateCommunityPostDto {
  @ApiPropertyOptional({ description: 'Post title' })
  @IsOptional()
  @IsString()
  title?: string;

  @ApiPropertyOptional({ description: 'Post body content' })
  @IsOptional()
  @IsString()
  body?: string;

  @ApiPropertyOptional({ description: 'Media URLs', type: [String] })
  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  mediaUrls?: string[];

  @ApiPropertyOptional({ description: 'Whether the post is pinned' })
  @IsOptional()
  @IsBoolean()
  isPinned?: boolean;

  @ApiPropertyOptional({ description: 'Whether the post is locked' })
  @IsOptional()
  @IsBoolean()
  isLocked?: boolean;
}
