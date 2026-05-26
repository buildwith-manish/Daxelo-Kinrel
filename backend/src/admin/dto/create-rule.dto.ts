import { IsString, IsOptional, IsIn, IsBoolean, Length } from 'class-validator';

const VALID_ACTIONS = ['allow', 'allow_with_flag', 'quarantine', 'reject', 'escalate', 'report_to_authorities'] as const;
const VALID_PRIORITIES = ['low', 'normal', 'high', 'urgent', 'critical'] as const;

export class CreateRuleDto {
  @IsString()
  @Length(1, 200)
  name!: string;

  @IsOptional()
  @IsString()
  description?: string;

  @IsOptional()
  @IsString()
  contentType?: string;

  @IsString()
  category!: string;

  @IsString()
  condition!: string; // JSON

  @IsString()
  @IsIn(VALID_ACTIONS)
  action!: string;

  @IsOptional()
  @IsString()
  @IsIn(VALID_PRIORITIES)
  priority?: string = 'normal';

  @IsOptional()
  @IsBoolean()
  isActive?: boolean = true;
}
