import { IsOptional, IsString, IsEnum, MaxLength } from 'class-validator';
import { Transform } from 'class-transformer';

export class KinshipQueryDto {
  @IsOptional()
  @IsString()
  @MaxLength(50)
  key?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  search?: string;

  @IsOptional()
  @IsString()
  @IsEnum([
    'immediate_family',
    'extended_paternal',
    'extended_maternal',
    'in_laws',
    'by_marriage',
  ])
  category?: string;

  @IsOptional()
  @IsString()
  @Transform(({ value }) => value?.toLowerCase())
  @IsEnum(['male', 'female', 'neutral'])
  gender?: string;

  @IsOptional()
  @IsString()
  @Transform(({ value }) => value?.toLowerCase())
  @IsEnum(['paternal', 'maternal', 'neutral'])
  lineage?: string;
}
