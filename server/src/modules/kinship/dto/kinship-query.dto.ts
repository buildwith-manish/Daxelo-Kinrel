import { IsOptional, IsString, IsEnum } from 'class-validator';
import { Transform } from 'class-transformer';

export class KinshipQueryDto {
  @IsOptional()
  @IsString()
  key?: string;

  @IsOptional()
  @IsString()
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
