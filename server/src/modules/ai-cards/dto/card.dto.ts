import { IsOptional, IsString, MaxLength } from 'class-validator';

export class FestivalCardDto {
  @IsString()
  @MaxLength(50)
  festival!: string;

  @IsOptional()
  @IsString()
  @MaxLength(50)
  kinshipTerm?: string;

  @IsOptional()
  @IsString()
  @MaxLength(10)
  language?: string;

  @IsOptional()
  @IsString()
  @MaxLength(30)
  style?: string;
}

export class KinshipCardDto {
  @IsString()
  @MaxLength(50)
  relationshipKey!: string;

  @IsOptional()
  @IsString()
  @MaxLength(10)
  language?: string;

  @IsOptional()
  @IsString()
  @MaxLength(30)
  style?: string;
}
