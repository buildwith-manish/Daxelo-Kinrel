import { IsString, IsOptional, IsEnum, MaxLength } from 'class-validator';

export class UpdateProfileDto {
  @IsString()
  @IsOptional()
  @MaxLength(100)
  name?: string;

  @IsString()
  @IsOptional()
  phone?: string;

  @IsString()
  @IsOptional()
  avatarUrl?: string;

  @IsString()
  @IsOptional()
  @MaxLength(300)
  bio?: string;

  @IsString()
  @IsOptional()
  dateOfBirth?: string;

  @IsString()
  @IsOptional()
  gender?: string;

  @IsString()
  @IsOptional()
  @MaxLength(50)
  username?: string;

  @IsString()
  @IsOptional()
  preferredLanguage?: string;

  @IsEnum(['public', 'private', 'connections-only'])
  @IsOptional()
  profileVisibility?: string;

  @IsEnum(['anyone', 'members-only', 'admin-only'])
  @IsOptional()
  invitePermission?: string;
}
