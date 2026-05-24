import {
  IsString,
  IsOptional,
  IsBoolean,
  IsEnum,
  MaxLength,
} from 'class-validator';
import { Type } from 'class-transformer';

export class UpdatePersonDto {
  @IsOptional()
  @IsString()
  @MaxLength(200, { message: 'Person name must not exceed 200 characters' })
  name?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100, { message: 'Relationship key must not exceed 100 characters' })
  relationship?: string;

  @IsOptional()
  @IsString()
  dateOfBirth?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(100, { message: 'Gotra must not exceed 100 characters' })
  gotra?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(200, { message: 'Occupation must not exceed 200 characters' })
  occupation?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(200, { message: 'City must not exceed 200 characters' })
  city?: string | null;

  @IsOptional()
  @Type(() => Boolean)
  @IsBoolean()
  isDeceased?: boolean;

  @IsOptional()
  @IsEnum(['family', 'extended', 'public'], {
    message: 'Privacy level must be one of: family, extended, public',
  })
  privacyLevel?: 'family' | 'extended' | 'public';
}
