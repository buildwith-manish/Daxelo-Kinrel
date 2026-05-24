import { IsOptional, IsString, IsNumber, Min, Max, IsInt } from 'class-validator';

export class GenerateQuizDto {
  @IsOptional()
  @IsString()
  category?: string;

  @IsOptional()
  @IsString()
  language?: string;

  @IsOptional()
  @IsNumber()
  @Min(1)
  @Max(20)
  count?: number;

  @IsOptional()
  @IsString()
  difficulty?: string; // 'easy', 'medium', 'hard'
}
