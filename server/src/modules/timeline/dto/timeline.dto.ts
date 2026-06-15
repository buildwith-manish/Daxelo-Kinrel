import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsString,
  IsNotEmpty,
  IsOptional,
  IsIn,
  IsObject,
  MaxLength,
} from 'class-validator';

// ── Create Post DTO ────────────────────────────────────────────────

export class CreatePostDto {
  @ApiProperty({
    description: 'Post type',
    enum: [
      'relationship_discovered',
      'member_joined',
      'milestone',
      'connection_added',
      'invite_shared',
      'update',
      'photo',
      'announcement',
    ],
  })
  @IsString()
  @IsNotEmpty()
  @IsIn([
    'relationship_discovered',
    'member_joined',
    'milestone',
    'connection_added',
    'invite_shared',
    'update',
    'photo',
    'announcement',
  ])
  postType!: string;

  @ApiProperty({ description: 'Post content as a JSON object' })
  @IsObject()
  content!: Record<string, any>;
}

// ── React DTO ──────────────────────────────────────────────────────

export class ReactDto {
  @ApiProperty({
    description: 'Unicode emoji to react with',
    example: '\u2764\uFE0F',
  })
  @IsString()
  @IsNotEmpty()
  emoji!: string;
}

// ── Create Comment DTO ─────────────────────────────────────────────

export class CreateCommentDto {
  @ApiProperty({ description: 'Comment body text', maxLength: 1000 })
  @IsString()
  @IsNotEmpty()
  @MaxLength(1000)
  body!: string;

  @ApiPropertyOptional({ description: 'Parent comment ID for threaded replies' })
  @IsOptional()
  @IsString()
  parentId?: string;
}
