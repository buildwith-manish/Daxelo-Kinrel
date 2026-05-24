import { IsString, IsOptional } from 'class-validator';

export class GenerateFestivalCardDto {
  @IsString()
  festival!: string;

  @IsString()
  kinshipTerm!: string;

  @IsOptional()
  @IsString()
  language?: string;

  @IsOptional()
  @IsString()
  style?: string;
}

export class GenerateKinshipCardDto {
  @IsString()
  relationshipKey!: string;

  @IsOptional()
  @IsString()
  language?: string;

  @IsOptional()
  @IsString()
  style?: string;
}
