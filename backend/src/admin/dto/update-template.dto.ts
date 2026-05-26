import { IsString, IsOptional, IsIn, IsArray, ArrayMinSize, Length } from 'class-validator';

const VALID_CATEGORIES = ['AUTHENTICATION', 'UTILITY', 'MARKETING', 'SERVICE'] as const;

export class UpdateTemplateDto {
  @IsOptional()
  @IsString()
  @Length(1, 200)
  name?: string;

  @IsOptional()
  @IsString()
  @IsIn(VALID_CATEGORIES)
  category?: string;

  @IsOptional()
  @IsArray()
  @ArrayMinSize(1)
  @IsString({ each: true })
  languages?: string[];

  @IsOptional()
  @IsString()
  components?: string; // JSON

  @IsOptional()
  @IsString()
  status?: string;
}
