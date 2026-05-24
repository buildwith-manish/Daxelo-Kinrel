import { IsString, IsOptional, IsInt, Min, Max, IsBoolean, MinLength } from 'class-validator';
import { Type } from 'class-transformer';

export class KbQueryDto {
  @IsOptional()
  @IsString()
  category?: string;

  @IsOptional()
  @IsString()
  lang?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number;

  @IsOptional()
  @IsString()
  slug?: string;
}

export class KbSearchDto {
  @IsString()
  @MinLength(2)
  q!: string;

  @IsOptional()
  @IsString()
  lang?: string;

  @IsOptional()
  @IsString()
  category?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(20)
  limit?: number;
}

export class KbHelpfulDto {
  @IsString()
  slug!: string;

  @IsBoolean()
  helpful!: boolean;
}
