import { IsOptional, IsString, IsBoolean, IsEnum, IsIn } from 'class-validator';
import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

// ── Update Privacy Settings DTO ──────────────────────────────────────

export class UpdatePrivacySettingsDto {
  @ApiPropertyOptional({ description: 'Profile visibility level' })
  @IsOptional()
  @IsIn(['family_only', 'extended', 'public'])
  visibility?: string;

  @ApiPropertyOptional({ description: 'Whether profile is searchable' })
  @IsOptional()
  @IsBoolean()
  searchable?: boolean;

  @ApiPropertyOptional({ description: 'Whether eligible for matrimonial features' })
  @IsOptional()
  @IsBoolean()
  matrimonialEligible?: boolean;

  @ApiPropertyOptional({ description: 'Whether community features are enabled' })
  @IsOptional()
  @IsBoolean()
  communityFeatures?: boolean;

  @ApiPropertyOptional({ description: 'Whether this person is a minor' })
  @IsOptional()
  @IsBoolean()
  minorFlag?: boolean;

  @ApiPropertyOptional({ description: 'Whether photo consent is given' })
  @IsOptional()
  @IsBoolean()
  photoConsent?: boolean;

  @ApiPropertyOptional({ description: 'Whether health data consent is given' })
  @IsOptional()
  @IsBoolean()
  healthConsent?: boolean;

  @ApiPropertyOptional({ description: 'Gotra visibility level' })
  @IsOptional()
  @IsIn(['self', 'admin', 'family', 'hidden'])
  gotraVisibility?: string;

  @ApiPropertyOptional({ description: 'Show phone number' })
  @IsOptional()
  @IsBoolean()
  showPhone?: boolean;

  @ApiPropertyOptional({ description: 'Show email address' })
  @IsOptional()
  @IsBoolean()
  showEmail?: boolean;

  @ApiPropertyOptional({ description: 'Show physical address' })
  @IsOptional()
  @IsBoolean()
  showAddress?: boolean;

  @ApiPropertyOptional({ description: 'Show date of birth' })
  @IsOptional()
  @IsBoolean()
  showDob?: boolean;

  @ApiPropertyOptional({ description: 'Show age' })
  @IsOptional()
  @IsBoolean()
  showAge?: boolean;

  @ApiPropertyOptional({ description: 'Show occupation' })
  @IsOptional()
  @IsBoolean()
  showOccupation?: boolean;

  @ApiPropertyOptional({ description: 'Show education' })
  @IsOptional()
  @IsBoolean()
  showEducation?: boolean;

  @ApiPropertyOptional({ description: 'Show blood group' })
  @IsOptional()
  @IsBoolean()
  showBloodGroup?: boolean;

  @ApiPropertyOptional({ description: 'Show anniversary date' })
  @IsOptional()
  @IsBoolean()
  showAnniversary?: boolean;

  @ApiPropertyOptional({ description: 'Profile visible to' })
  @IsOptional()
  @IsIn(['family', 'extended', 'public'])
  profileVisibleTo?: string;
}

// ── Kinship Graph Query DTO ──────────────────────────────────────────

export class KinshipGraphQueryDto {
  @ApiPropertyOptional({ description: 'Filter by relationship category' })
  @IsOptional()
  @IsString()
  category?: string;

  @ApiPropertyOptional({ description: 'Filter by lineage' })
  @IsOptional()
  @IsIn(['paternal', 'maternal', 'neutral'])
  lineage?: string;

  @ApiPropertyOptional({ description: 'Filter by relationship classification' })
  @IsOptional()
  @IsIn(['blood', 'marital', 'affinal'])
  relationType?: string;

  @ApiPropertyOptional({ description: 'Minimum kinship coefficient threshold (0-1)' })
  @IsOptional()
  @IsString()
  minCoefficient?: string;

  @ApiPropertyOptional({ description: 'Maximum graph distance (hops)' })
  @IsOptional()
  @IsString()
  maxDistance?: string;

  @ApiPropertyOptional({ description: 'Include multilingual translations' })
  @IsOptional()
  @IsString()
  includeTranslations?: string;

  @ApiPropertyOptional({ description: 'Locale for kinship term resolution' })
  @IsOptional()
  @IsString()
  locale?: string;
}
