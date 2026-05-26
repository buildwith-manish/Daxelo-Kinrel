import { IsString, IsOptional, IsInt, Min, Max, Length } from 'class-validator';
import { Type } from 'class-transformer';

export class SearchArticlesDto {
  @IsString()
  @Length(2, 200)
  q!: string;

  @IsOptional()
  @IsString()
  language?: string = 'en';

  @IsOptional()
  @IsString()
  category?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(20)
  limit?: number = 10;
}
