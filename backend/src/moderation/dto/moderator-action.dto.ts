import { IsString, IsOptional, IsIn, Length } from 'class-validator';

const VALID_ACTIONS = ['approve', 'reject', 'restrict', 'escalate'] as const;

export class ModeratorActionDto {
  @IsString()
  caseId!: string;

  @IsString()
  @IsIn(VALID_ACTIONS)
  action!: string;

  @IsOptional()
  @IsString()
  @Length(0, 2000)
  notes?: string;
}
