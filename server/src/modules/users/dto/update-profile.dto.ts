import {
  IsOptional,
  IsString,
  MaxLength,
  MinLength,
  Matches,
  IsIn,
  IsUrl,
} from 'class-validator';

export class UpdateProfileDto {
  @IsOptional()
  @IsString()
  @MaxLength(100)
  name?: string;

  @IsOptional()
  @IsString()
  @MaxLength(20)
  phone?: string;

  @IsOptional()
  @IsString()
  @MaxLength(10)
  preferredLanguage?: string;

  @IsOptional()
  @IsString()
  @MinLength(3)
  @MaxLength(30)
  @Matches(/^[a-zA-Z0-9_]+$/)
  username?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  bio?: string;

  @IsOptional()
  @IsString()
  @MaxLength(20)
  dateOfBirth?: string;

  @IsOptional()
  @IsString()
  @IsIn(['male', 'female', 'non-binary', 'prefer-not-to-say'])
  gender?: string;

  @IsOptional()
  @IsString()
  @IsUrl()
  @MaxLength(500)
  avatarUrl?: string;

  @IsOptional()
  @IsString()
  @IsIn(['public', 'connections_only', 'private'])
  profileVisibility?: string;

  @IsOptional()
  @IsString()
  @IsIn(['anyone', 'connections', 'nobody'])
  invitePermission?: string;
}
