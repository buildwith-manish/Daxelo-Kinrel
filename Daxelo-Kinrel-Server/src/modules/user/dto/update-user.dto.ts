import {
  IsString,
  IsOptional,
  MinLength,
  MaxLength,
  IsIn,
} from 'class-validator';

/**
 * Supported languages in the DAXELO KINREL platform.
 * Can be extended as more languages are added.
 */
const SUPPORTED_LANGUAGES = ['en', 'hi', 'mr', 'bn', 'ta', 'te', 'gu', 'kn', 'ml', 'pa', 'or', 'as', 'ur', 'sa'];

export class UpdateUserDto {
  @IsOptional()
  @IsString({ message: 'Name must be a string' })
  @MinLength(1, { message: 'Name must not be empty' })
  @MaxLength(200, { message: 'Name must not exceed 200 characters' })
  name?: string;

  @IsOptional()
  @IsString({ message: 'Phone must be a string' })
  @MaxLength(50, { message: 'Phone must not exceed 50 characters' })
  phone?: string | null;

  @IsOptional()
  @IsString({ message: 'Preferred language must be a string' })
  @MaxLength(10, { message: 'Language code must not exceed 10 characters' })
  preferredLanguage?: string;
}
