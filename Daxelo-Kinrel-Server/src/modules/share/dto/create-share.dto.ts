import { IsString, IsOptional, IsEnum, IsUrl, MaxLength, MinLength } from 'class-validator';

export class CreateShareDto {
  @IsEnum([
    'family_tree',
    'birthday',
    'anniversary',
    'memorial',
    'milestone',
    'relationship_discovery',
    'festival_greeting',
  ])
  cardType!: string;

  @IsOptional()
  @IsString()
  familyId?: string;

  @IsOptional()
  @IsString()
  personId?: string;

  @IsString()
  @MinLength(1)
  @MaxLength(200)
  title!: string;

  @IsString()
  @MinLength(1)
  @MaxLength(500)
  description!: string;

  @IsUrl()
  deepLinkUrl!: string;

  @IsOptional()
  @IsString()
  expiresAt?: string;
}
