import { IsOptional, IsString, IsIn, IsDateString, MaxLength } from 'class-validator';

const SUPPORTED_LANGUAGES = [
  'en', 'hi', 'bn', 'te', 'mr', 'ta', 'ur', 'gu', 'kn', 'ml', 'or', 'pa', 'as', 'sa',
];

export class UpdateProfileDto {
  @IsOptional()
  @IsString()
  @MaxLength(100)
  name?: string;

  @IsOptional()
  @IsString()
  phone?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  bio?: string;

  @IsOptional()
  @IsDateString()
  dateOfBirth?: string;

  @IsOptional()
  @IsIn(['Male', 'Female', 'Other', 'Prefer not to say'])
  gender?: string;

  @IsOptional()
  @IsIn(SUPPORTED_LANGUAGES)
  preferredLanguage?: string;

  @IsOptional()
  @IsIn(['public', 'private'])
  profileVisibility?: string;

  @IsOptional()
  @IsIn(['everyone', 'mutual', 'nobody'])
  invitePermission?: string;
}
