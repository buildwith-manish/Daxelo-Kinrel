import { IsString, IsOptional, IsIn, IsUrl, MaxLength } from 'class-validator';

export class CreateShareableLinkDto {
  @IsIn([
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
  @MaxLength(200)
  title!: string;

  @IsString()
  @MaxLength(500)
  description!: string;

  @IsUrl()
  deepLinkUrl!: string;

  @IsOptional()
  @IsString()
  expiresAt?: string; // ISO datetime string
}
