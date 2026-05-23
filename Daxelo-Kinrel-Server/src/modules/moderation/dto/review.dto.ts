import { IsString, IsOptional, IsEnum } from 'class-validator';

export class ReviewDto {
  @IsString()
  caseId!: string;

  @IsString()
  moderatorId!: string;

  @IsEnum(['approve', 'reject', 'restrict', 'escalate'])
  action!: string;

  @IsOptional()
  @IsString()
  notes?: string;

  @IsOptional()
  @IsString()
  contentAction?: string;
}
