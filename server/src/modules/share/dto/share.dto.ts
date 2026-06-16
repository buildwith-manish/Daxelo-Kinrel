import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import {
  IsString,
  IsNotEmpty,
  IsOptional,
  IsIn,
  IsInt,
  Min,
  Max,
  MaxLength,
} from 'class-validator';

const VALID_CARD_TYPES = [
  'family_tree',
  'birthday',
  'anniversary',
  'memorial',
  'milestone',
  'relationship_discovery',
  'festival_greeting',
] as const;

export class CreateShareableLinkDto {
  @ApiProperty({
    description: 'Card type for the shareable link',
    enum: VALID_CARD_TYPES,
  })
  @IsString()
  @IsNotEmpty()
  @IsIn(VALID_CARD_TYPES)
  cardType!: string;

  @ApiPropertyOptional({ description: 'Family ID to associate with the link' })
  @IsOptional()
  @IsString()
  familyId?: string;

  @ApiPropertyOptional({ description: 'Person ID to associate with the link' })
  @IsOptional()
  @IsString()
  personId?: string;

  @ApiProperty({ description: 'Title for the shared card' })
  @IsString()
  @IsNotEmpty()
  @MaxLength(200)
  title!: string;

  @ApiPropertyOptional({ description: 'Description for the shared card' })
  @IsOptional()
  @IsString()
  @MaxLength(1000)
  description?: string;

  @ApiPropertyOptional({ description: 'Deep link URL (auto-generated if omitted)' })
  @IsOptional()
  @IsString()
  deepLinkUrl?: string;

  @ApiPropertyOptional({
    description: 'Number of days until the link expires (1-365)',
    minimum: 1,
    maximum: 365,
  })
  @IsOptional()
  @IsInt()
  @Min(1)
  @Max(365)
  expiresInDays?: number;
}

export class TrackShareDto {
  @ApiProperty({ description: 'Token of the shareable link that was shared' })
  @IsString()
  @IsNotEmpty()
  token!: string;
}
