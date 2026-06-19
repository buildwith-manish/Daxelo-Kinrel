import {
  IsString,
  IsNotEmpty,
  IsOptional,
  IsBoolean,
  IsInt,
  IsDateString,
  IsIn,
  MaxLength,
} from 'class-validator';
import { Transform } from 'class-transformer';

export class CreateMemberDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  name!: string;

  @IsOptional()
  @IsIn(['male', 'female', 'other', 'non-binary', 'prefer not to say'])
  gender?: string;

  @IsOptional()
  @IsDateString()
  dateOfBirth?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  city?: string;

  @IsOptional()
  @IsString()
  @MaxLength(50)
  gotra?: string;

  @IsOptional()
  @Transform(({ value }) => (value !== undefined ? parseInt(value, 10) : undefined))
  @IsInt()
  birthYear?: number;

  @IsOptional()
  @IsBoolean()
  @Transform(({ value }) => value === 'true' || value === true)
  isAnchor?: boolean;

  @IsOptional()
  @IsIn(['paternal', 'maternal', 'both'])
  sideOfFamily?: string;

  @IsOptional()
  @Transform(({ value }) => (value !== undefined ? parseInt(value, 10) : 0))
  @IsInt()
  generationIndex?: number;

  /**
   * If provided, automatically creates a bidirectional relationship between
   * the newly added member and this existing person in the family.
   * Must be used together with initialRelationshipKey.
   */
  @IsOptional()
  @IsString()
  relativePersonId?: string;

  /**
   * The core relationship key describing how the new member relates TO the
   * relativePersonId. Only core types are allowed:
   * father, mother, son, daughter, brother, sister, husband, wife
   *
   * Example: if the new member is the SON of relativePersonId,
   * set initialRelationshipKey = 'son'.
   */
  @IsOptional()
  @IsIn(['father', 'mother', 'son', 'daughter', 'brother', 'sister', 'husband', 'wife'])
  initialRelationshipKey?: string;
}
