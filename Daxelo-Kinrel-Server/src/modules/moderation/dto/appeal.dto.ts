import { IsString, IsEnum, IsOptional, MinLength, MaxLength } from 'class-validator';

export class AppealDto {
  @IsString()
  caseId!: string;

  @IsString()
  appellantId!: string;

  @IsString()
  @MinLength(10)
  @MaxLength(2000)
  appealReason!: string;
}

export class AppealReviewDto {
  @IsString()
  reviewerId!: string;

  @IsEnum(['upheld', 'reinstated', 'reduced', 'dismissed'])
  decision!: string;

  @IsString()
  @IsOptional()
  notes?: string;
}
