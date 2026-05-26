import { IsString, IsOptional, IsIn, Length } from 'class-validator';

const VALID_DECISIONS = ['upheld', 'reinstated', 'reduced', 'dismissed'] as const;

export class AppealReviewDto {
  @IsString()
  @IsIn(VALID_DECISIONS)
  reviewDecision!: string;

  @IsOptional()
  @IsString()
  @Length(0, 2000)
  reviewNotes?: string;
}
