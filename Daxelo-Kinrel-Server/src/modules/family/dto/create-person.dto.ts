import {
  IsString,
  IsOptional,
  IsBoolean,
  IsEnum,
  MinLength,
  MaxLength,
  IsNotEmpty,
} from 'class-validator';
import { Type } from 'class-transformer';

export class CreatePersonDto {
  @IsString()
  @IsNotEmpty({ message: 'Person name is required' })
  @MinLength(1, { message: 'Person name must not be empty' })
  @MaxLength(200, { message: 'Person name must not exceed 200 characters' })
  name!: string;

  @IsString()
  @IsNotEmpty({ message: 'Relationship key is required' })
  @MinLength(1, { message: 'Relationship key must not be empty' })
  @MaxLength(100, { message: 'Relationship key must not exceed 100 characters' })
  relationship!: string;

  @IsOptional()
  @IsString()
  dateOfBirth?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100, { message: 'Gotra must not exceed 100 characters' })
  gotra?: string;

  @IsOptional()
  @IsString()
  @MaxLength(200, { message: 'Occupation must not exceed 200 characters' })
  occupation?: string;

  @IsOptional()
  @IsString()
  @MaxLength(200, { message: 'City must not exceed 200 characters' })
  city?: string;

  @IsOptional()
  @Type(() => Boolean)
  @IsBoolean()
  isDeceased?: boolean = false;

  @IsOptional()
  @IsEnum(['family', 'extended', 'public'], {
    message: 'Privacy level must be one of: family, extended, public',
  })
  privacyLevel?: 'family' | 'extended' | 'public' = 'family';
}
