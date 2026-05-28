import { IsOptional, IsString } from 'class-validator';

export class FestivalCardDto {
  @IsString()
  festival!: string;

  @IsOptional()
  @IsString()
  kinshipTerm?: string;

  @IsOptional()
  @IsString()
  language?: string;

  @IsOptional()
  @IsString()
  style?: string;
}

export class KinshipCardDto {
  @IsString()
  relationshipKey!: string;

  @IsOptional()
  @IsString()
  language?: string;

  @IsOptional()
  @IsString()
  style?: string;
}
