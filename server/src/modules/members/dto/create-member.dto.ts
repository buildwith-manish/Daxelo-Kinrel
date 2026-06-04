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
  @IsIn(['male', 'female', 'other'])
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
}
