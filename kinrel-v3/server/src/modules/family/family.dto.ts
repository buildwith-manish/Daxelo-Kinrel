/**
 * Daxelo-Kinrel — DTOs for FamilyController & friends.
 */
import { IsString, IsEnum, IsOptional, IsDateString, IsBoolean, MaxLength } from "class-validator";

export enum GenderDto {
  MALE = "MALE",
  FEMALE = "FEMALE",
  OTHER = "OTHER",
}

export enum EdgeTypeDto {
  PARENT = "PARENT",
  SPOUSE = "SPOUSE",
  ADOPTIVE_PARENT = "ADOPTIVE_PARENT",
  STEP_PARENT = "STEP_PARENT",
}

export enum EdgeTemporalDto {
  CURRENT = "CURRENT",
  FORMER = "FORMER",
  LATE = "LATE",
}

export class CreateFamilyDto {
  @IsString() @MaxLength(200)
  name!: string;
}

export class CreatePersonDto {
  @IsString() @MaxLength(200)
  fullName!: string;
  @IsEnum(GenderDto)
  gender!: GenderDto;
  @IsOptional() @IsDateString()
  birthDate?: string;
  @IsOptional() @IsDateString()
  deathDate?: string;
  @IsOptional() @IsBoolean()
  isAdopted?: boolean;
}

export class CreateRelationshipDto {
  @IsString()
  familyId!: string;
  @IsString()
  personAId!: string;
  @IsString()
  personBId!: string;

  /** Either edgeType OR detectedTerm must be provided. */
  @IsOptional() @IsEnum(EdgeTypeDto)
  edgeType?: EdgeTypeDto;
  @IsOptional() @IsString()
  detectedTerm?: string;
  @IsOptional() @IsString()
  locale?: string;
  @IsOptional() @IsEnum(EdgeTemporalDto)
  temporal?: EdgeTemporalDto;
  @IsOptional() @IsBoolean()
  isInferred?: boolean;
}

export class DetectRelationshipDto {
  @IsString()
  familyId!: string;
  @IsString()
  personAId!: string;
  @IsString()
  personBId!: string;
  @IsOptional() @IsString()
  locale?: string;
}

export class ResolveKinshipDto {
  @IsString()
  familyId!: string;
  @IsString()
  personAId!: string;
  @IsString()
  personBId!: string;
  @IsOptional() @IsString()
  locale?: string;
}

export class GetTreeDto {
  @IsString()
  familyId!: string;
  @IsString()
  rootPersonId!: string;
  @IsOptional() @IsString()
  locale?: string;
  @IsOptional()
  upDepth?: number;
  @IsOptional()
  downDepth?: number;
}

export class InferSpouseDto {
  @IsString()
  familyId!: string;
  @IsString()
  personAId!: string;
  @IsString()
  personBId!: string;
}
