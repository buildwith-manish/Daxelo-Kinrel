import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsString, IsOptional, IsIn, IsInt, Min, Max, IsDateString } from 'class-validator';
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

  @ApiPropertyOptional({ description: 'Audience scope', enum: ['PUBLIC', 'FAMILY_ONLY'] })
  @IsOptional() @IsIn(['PUBLIC', 'FAMILY_ONLY'])
  audience?: string;
}

export class SparqFeedDto {
  @ApiPropertyOptional({ default: 1 })
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) page?: number = 1;

  @ApiPropertyOptional({ default: 20 })
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(100) limit?: number = 20;
}
