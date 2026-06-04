import { IsArray, IsString, IsOptional, MaxLength, ArrayMaxSize } from 'class-validator';

export class ExplainRelationshipDto {
  @IsArray()
  @IsString({ each: true })
  @ArrayMaxSize(20)
  path!: string[];

  @IsOptional()
  @IsString()
  @MaxLength(100)
  fromPersonName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  toPersonName?: string;

  @IsOptional()
  @IsString()
  @MaxLength(10)
  language?: string; // en, hi, etc.
}
