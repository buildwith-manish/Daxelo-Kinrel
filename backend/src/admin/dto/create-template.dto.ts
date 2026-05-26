import { IsString, IsArray, IsIn, ArrayMinSize, IsOptional, Length } from 'class-validator';

const VALID_CATEGORIES = ['AUTHENTICATION', 'UTILITY', 'MARKETING', 'SERVICE'] as const;

export class CreateTemplateDto {
  @IsString()
  @Length(1, 200)
  name!: string;

  @IsString()
  @IsIn(VALID_CATEGORIES)
  category!: string;

  @IsArray()
  @ArrayMinSize(1)
  @IsString({ each: true })
  languages!: string[];

  @IsString()
  components!: string; // JSON

  @IsOptional()
  @IsString()
  @Length(0, 500)
  description?: string;
}
