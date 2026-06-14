import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';

// ── Kinship Translation ──────────────────────────────────────────────

export class KinshipTranslationDto {
  @ApiProperty() native: string;
  @ApiProperty() latin: string;
}

// ── Individual Kinship Relationship ──────────────────────────────────

export class KinshipRelationshipDto {
  @ApiProperty() personId: string;
  @ApiProperty() personName: string;
  @ApiProperty({ description: 'Gender of the related person' }) gender: string | null;
  @ApiProperty({ description: 'Raw relationship key path (e.g., "father→brother→son")' }) relationshipKey: string;
  @ApiProperty({ description: 'Computed kinship term (e.g., "cousin")' }) computedTerm: string;
  @ApiProperty({ description: 'Computed kinship term in Hindi' }) computedTermHindi: string;
  @ApiPropertyOptional({ description: 'Multilingual translations keyed by language code' }) translations?: Record<string, KinshipTranslationDto>;
  @ApiProperty({ description: 'Coefficient of relationship (0.0 to 1.0)', example: 0.125 }) kinshipCoefficient: number;
  @ApiProperty({ description: 'Graph distance in hops' }) distance: number;
  @ApiProperty({ description: 'Lineage classification' }) lineage: 'paternal' | 'maternal' | 'neutral';
  @ApiProperty({ description: 'Relationship classification' }) relationType: 'blood' | 'marital' | 'affinal';
  @ApiPropertyOptional({ description: 'Relationship category from kinship database' }) category?: string;
  @ApiProperty({ description: 'Whether the person is deceased' }) isDeceased: boolean;
  @ApiPropertyOptional({ description: 'Photo thumbnail URL' }) photoThumb?: string | null;
  @ApiPropertyOptional({ description: 'Generation index' }) generationIndex?: number;
}

// ── Kinship Summary Statistics ────────────────────────────────────────

export class KinshipSummaryDto {
  @ApiProperty() totalRelationships: number;
  @ApiProperty() immediateFamily: number;
  @ApiProperty() extendedFamily: number;
  @ApiProperty() inLaws: number;
  @ApiProperty() byMarriage: number;
  @ApiProperty({ description: 'Average kinship coefficient across all relationships' }) averageKinshipCoefficient: number;
  @ApiProperty({ description: 'Highest coefficient among non-self relationships' }) maxKinshipCoefficient: number;
  @ApiPropertyOptional({ description: 'Closest blood relationship details' }) closestRelationship: {
    term: string;
    termHindi: string;
    coefficient: number;
    personName: string;
  } | null;
  @ApiProperty({ description: 'Maximum generation depth in the graph' }) kinshipDepth: number;
  @ApiProperty({ description: 'Count of blood relationships' }) bloodRelations: number;
  @ApiProperty({ description: 'Count of marital relationships' }) maritalRelations: number;
  @ApiProperty({ description: 'Count of affinal relationships' }) affinalRelations: number;
}

// ── Person Profile (privacy-filtered) ────────────────────────────────

export class PersonProfileDto {
  @ApiProperty() id: string;
  @ApiProperty() familyId: string;
  @ApiProperty() name: string;
  @ApiPropertyOptional() gender: string | null;
  @ApiPropertyOptional() dateOfBirth: string | null;
  @ApiPropertyOptional() city: string | null;
  @ApiPropertyOptional() gotra: string | null;
  @ApiProperty() isDeceased: boolean;
  @ApiPropertyOptional() birthYear: number | null;
  @ApiPropertyOptional() occupation: string | null;
  @ApiProperty() privacyLevel: string;
  @ApiPropertyOptional() sideOfFamily: string | null;
  @ApiProperty() generationIndex: number;
  @ApiProperty() isAnchor: boolean;
  @ApiPropertyOptional() photoUrl: string | null;
  @ApiPropertyOptional() photoThumb: string | null;
  @ApiPropertyOptional() username: string | null;
  // Privacy-filtered fields — only shown based on viewer permissions
  @ApiPropertyOptional() email?: string | null;
  @ApiPropertyOptional() phone?: string | null;
  @ApiPropertyOptional() address?: string | null;
  @ApiPropertyOptional() bloodGroup?: string | null;
  @ApiPropertyOptional() anniversaryDate?: string | null;
  @ApiPropertyOptional() education?: string | null;
  @ApiPropertyOptional() biography?: string | null;
  @ApiPropertyOptional() notes?: string | null;
}

// ── Privacy Settings ─────────────────────────────────────────────────

export class PrivacySettingsDto {
  @ApiProperty() visibility: string;
  @ApiProperty() searchable: boolean;
  @ApiProperty() matrimonialEligible: boolean;
  @ApiProperty() communityFeatures: boolean;
  @ApiProperty() minorFlag: boolean;
  @ApiProperty() photoConsent: boolean;
  @ApiProperty() healthConsent: boolean;
  @ApiProperty() gotraVisibility: string;
  @ApiProperty() showPhone: boolean;
  @ApiProperty() showEmail: boolean;
  @ApiProperty() showAddress: boolean;
  @ApiProperty() showDob: boolean;
  @ApiProperty() showAge: boolean;
  @ApiProperty() showOccupation: boolean;
  @ApiProperty() showEducation: boolean;
  @ApiProperty() showBloodGroup: boolean;
  @ApiProperty() showAnniversary: boolean;
  @ApiProperty() profileVisibleTo: string;
}

// ── Full Profile with Kinship Integration ────────────────────────────

export class ProfileWithKinshipDto {
  @ApiProperty() person: PersonProfileDto;
  @ApiPropertyOptional() privacy: PrivacySettingsDto | null;
  @ApiProperty() kinshipSummary: KinshipSummaryDto;
  @ApiProperty({ type: [KinshipRelationshipDto] }) kinshipGraph: KinshipRelationshipDto[];
  @ApiPropertyOptional({ description: 'Viewer role relative to this person' }) viewerRole: 'self' | 'admin' | 'member' | 'extended' | 'public';
  @ApiProperty() readOnly: boolean;
}

// ── Kinship Graph Response (paginated) ───────────────────────────────

export class KinshipGraphResponseDto {
  @ApiProperty({ type: [KinshipRelationshipDto] }) items: KinshipRelationshipDto[];
  @ApiProperty() total: number;
  @ApiProperty() summary: KinshipSummaryDto;
  @ApiPropertyOptional() nextCursor?: string | null;
}
