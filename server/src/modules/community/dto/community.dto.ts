import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsString,
  IsOptional,
  IsNotEmpty,
  IsIn,
  IsBoolean,
  IsInt,
  Min,
  Max,
} from 'class-validator';
import { Transform, Type } from 'class-transformer';

export class CreateCommunityDto {
  @ApiProperty({
    description: 'Community type',
    enum: ['gotra', 'village', 'surname', 'custom'],
  })
  @IsString()
  @IsNotEmpty()
  @IsIn(['gotra', 'village', 'surname', 'custom'])
  type!: string;

  @ApiProperty({ description: 'Community name' })
  @IsString()
  @IsNotEmpty()
  name!: string;

  @ApiPropertyOptional({ description: 'Community description' })
  @IsOptional()
  @IsString()
  description?: string;

  @ApiPropertyOptional({ description: 'Whether the community is private', default: false })
  @IsOptional()
  @IsBoolean()
  @Transform(({ value }) => value === 'true' || value === true)
  isPrivate?: boolean;

  @ApiPropertyOptional({ description: 'Gotra name (for gotra type)' })
  @IsOptional()
  @IsString()
  gotraName?: string;

  @ApiPropertyOptional({ description: 'Village name (for village type)' })
  @IsOptional()
  @IsString()
  villageName?: string;

  @ApiPropertyOptional({ description: 'Surname (for surname type)' })
  @IsOptional()
  @IsString()
  surname?: string;

  @ApiPropertyOptional({ description: 'Region' })
  @IsOptional()
  @IsString()
  region?: string;

  @ApiPropertyOptional({ description: 'Cover image URL' })
  @IsOptional()
  @IsString()
  coverImageUrl?: string;

  @ApiPropertyOptional({ description: 'Icon URL' })
  @IsOptional()
  @IsString()
  iconUrl?: string;
}

export class UpdateCommunityDto {
  @ApiPropertyOptional({ description: 'Community type', enum: ['gotra', 'village', 'surname', 'custom'] })
  @IsOptional()
  @IsString()
  @IsIn(['gotra', 'village', 'surname', 'custom'])
  type?: string;

  @ApiPropertyOptional({ description: 'Community name' })
  @IsOptional()
  @IsString()
  @IsNotEmpty()
  name?: string;

  @ApiPropertyOptional({ description: 'Community description' })
  @IsOptional()
  @IsString()
  description?: string;

  @ApiPropertyOptional({ description: 'Whether the community is private' })
  @IsOptional()
  @IsBoolean()
  @Transform(({ value }) => value === 'true' || value === true)
  isPrivate?: boolean;

  @ApiPropertyOptional({ description: 'Gotra name' })
  @IsOptional()
  @IsString()
  gotraName?: string;

  @ApiPropertyOptional({ description: 'Village name' })
  @IsOptional()
  @IsString()
  villageName?: string;

  @ApiPropertyOptional({ description: 'Surname' })
  @IsOptional()
  @IsString()
  surname?: string;

  @ApiPropertyOptional({ description: 'Region' })
  @IsOptional()
  @IsString()
  region?: string;

  @ApiPropertyOptional({ description: 'Cover image URL' })
  @IsOptional()
  @IsString()
  coverImageUrl?: string;

  @ApiPropertyOptional({ description: 'Icon URL' })
  @IsOptional()
  @IsString()
  iconUrl?: string;
}

export class SearchCommunityDto {
  @ApiPropertyOptional({ description: 'Search query' })
  @IsOptional()
  @IsString()
  search?: string;

  @ApiPropertyOptional({ description: 'Filter by community type', enum: ['gotra', 'village', 'surname', 'custom'] })
  @IsOptional()
  @IsString()
  @IsIn(['gotra', 'village', 'surname', 'custom'])
  type?: string;

  @ApiPropertyOptional({ description: 'Page number', default: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number = 1;

  @ApiPropertyOptional({ description: 'Items per page', default: 20 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number = 20;
}

export class JoinCommunityDto {}
