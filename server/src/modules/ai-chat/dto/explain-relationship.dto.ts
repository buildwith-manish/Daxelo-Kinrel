import { IsArray, IsString, IsOptional } from 'class-validator';

export class ExplainRelationshipDto {
  @IsArray()
  @IsString({ each: true })
  path!: string[];

  @IsOptional()
  @IsString()
  fromPersonName?: string;

  @IsOptional()
  @IsString()
  toPersonName?: string;

  @IsOptional()
  @IsString()
  language?: string; // en, hi, etc.
}
