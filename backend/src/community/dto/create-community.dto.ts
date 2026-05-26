import { IsString, IsOptional, IsBoolean, Length } from 'class-validator';

export class CreateCommunityDto {
  @IsString()
  @Length(1, 200)
  type!: string;

  @IsString()
  @Length(1, 200)
  name!: string;

  @IsOptional()
  @IsString()
  @Length(0, 50)
  slug?: string;

  @IsOptional()
  @IsString()
  description?: string;

  @IsOptional()
  @IsString()
  gotraName?: string;

  @IsOptional()
  @IsString()
  villageName?: string;

  @IsOptional()
  @IsString()
  surname?: string;

  @IsOptional()
  @IsString()
  region?: string;

  @IsOptional()
  @IsBoolean()
  isPrivate?: boolean;
}
