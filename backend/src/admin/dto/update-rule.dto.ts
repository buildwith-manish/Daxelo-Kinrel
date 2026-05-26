import { IsString, IsOptional, IsIn, IsBoolean, Length } from 'class-validator';

const VALID_ACTIONS = ['allow', 'allow_with_flag', 'quarantine', 'reject', 'escalate', 'report_to_authorities'] as const;
const VALID_PRIORITIES = ['low', 'normal', 'high', 'urgent', 'critical'] as const;

export class UpdateRuleDto {
  @IsOptional()
  @IsString()
  @Length(1, 200)
  name?: string;

  @IsOptional()
  @IsString()
  description?: string;

  @IsOptional()
  @IsString()
  contentType?: string;

  @IsOptional()
  @IsString()
  category?: string;

  @IsOptional()
  @IsString()
  condition?: string;

  @IsOptional()
  @IsString()
  @IsIn(VALID_ACTIONS)
  action?: string;

  @IsOptional()
  @IsString()
  @IsIn(VALID_PRIORITIES)
  priority?: string;

  @IsOptional()
  @IsBoolean()
  isActive?: boolean;
}
