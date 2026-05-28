import { IsString, IsOptional, IsInt, IsBoolean, MaxLength } from 'class-validator';

export class UpdatePersonDto {
  @IsString()
  @IsOptional()
  @MaxLength(100)
  name?: string;

  @IsString()
  @IsOptional()
  gender?: string;

  @IsInt()
  @IsOptional()
  birthYear?: number;

  @IsBoolean()
  @IsOptional()
  isAnchor?: boolean;

  @IsInt()
  @IsOptional()
  generationIndex?: number;

  @IsString()
  @IsOptional()
  city?: string;

  @IsString()
  @IsOptional()
  gotra?: string;

  @IsBoolean()
  @IsOptional()
  isDeceased?: boolean;

  @IsString()
  @IsOptional()
  privacyLevel?: string;

  @IsString()
  @IsOptional()
  occupation?: string;

  @IsString()
  @IsOptional()
  @MaxLength(500)
  notes?: string;

  @IsString()
  @IsOptional()
  sideOfFamily?: string;

  @IsString()
  @IsOptional()
  photoUrl?: string;

  @IsString()
  @IsOptional()
  dateOfBirth?: string;
}
