import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsString, IsOptional, IsIn, IsInt, Min, Max, IsDateString, IsBoolean } from 'class-validator';
import { Type } from 'class-transformer';

export class CreateSparqDto {
  @ApiProperty({ description: 'Content type', enum: ['IMAGE', 'VIDEO', 'TEXT', 'VOICE'] })
  @IsIn(['IMAGE', 'VIDEO', 'TEXT', 'VOICE'])
  type!: string;

  @ApiPropertyOptional({ description: 'Text content for TEXT type' })
  @IsOptional() @IsString()
  text?: string;

  @ApiPropertyOptional({ description: 'Background color for TEXT type (hex)' })
  @IsOptional() @IsString()
  backgroundColor?: string;

  @ApiPropertyOptional({ description: 'Duration in seconds for VIDEO/VOICE' })
  @IsOptional() @Type(() => Number) @IsInt()
  duration?: number;

  @ApiPropertyOptional({ description: 'Audience scope', enum: ['PUBLIC', 'FAMILY_ONLY', 'VIP_CIRCLE'] })
  @IsOptional() @IsIn(['PUBLIC', 'FAMILY_ONLY', 'VIP_CIRCLE'])
  audience?: string;

  @ApiPropertyOptional({ description: 'Mood of the Sparq', enum: ['happy', 'hype', 'love', 'sad', 'celebrate', 'angry'], default: 'happy' })
  @IsOptional() @IsIn(['happy', 'hype', 'love', 'sad', 'celebrate', 'angry'])
  mood?: string;

  @ApiPropertyOptional({ description: 'Intensity level', enum: ['calm', 'warm', 'fire'], default: 'warm' })
  @IsOptional() @IsIn(['calm', 'warm', 'fire'])
  intensity?: string;

  @ApiPropertyOptional({ description: 'Whether other users can chain onto this Sparq', default: false })
  @IsOptional() @IsBoolean()
  allowChain?: boolean;

  @ApiPropertyOptional({ description: 'Whether replies are allowed on this Sparq', default: true })
  @IsOptional() @IsBoolean()
  allowReplies?: boolean;

  @ApiPropertyOptional({ description: 'Whether this is a Time Capsule Sparq', default: false })
  @IsOptional() @IsBoolean()
  isTimeCapsule?: boolean;

  @ApiPropertyOptional({ description: 'ISO date string when Time Capsule should be revealed (must be future)' })
  @IsOptional() @IsDateString()
  revealAt?: string;

  @ApiPropertyOptional({ description: 'UUID of parent Sparq for chaining' })
  @IsOptional() @IsString()
  parentSparqId?: string;
}

export class SparqFeedDto {
  @ApiPropertyOptional({ default: 1 })
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) page?: number = 1;

  @ApiPropertyOptional({ default: 20 })
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(100) limit?: number = 20;
}
