import { IsOptional, IsString, IsNumber, IsEnum, Min, Max } from 'class-validator';
import { Transform, Type } from 'class-transformer';

export class CreateQuizDto {
  @IsOptional()
  @IsString()
  @IsEnum(['kinship_basic', 'kinship_advanced', 'family_traditions', 'languages'])
  category?: string;

  @IsString()
  @IsEnum(['hi', 'en', 'mr', 'ta', 'te', 'kn', 'bn', 'gu'])
  language!: string;

  @IsNumber()
  @Type(() => Number)
  @Min(1)
  @Max(20)
  count!: number;

  @IsOptional()
  @IsString()
  @IsEnum(['easy', 'medium', 'hard'])
  difficulty?: string;
}

export class SubmitQuizDto {
  @IsNumber({}, { each: true })
  answers!: number[];
}
