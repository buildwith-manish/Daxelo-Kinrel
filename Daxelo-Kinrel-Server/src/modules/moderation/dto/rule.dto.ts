import { IsString, IsOptional, IsEnum, IsBoolean } from 'class-validator';

export class CreateRuleDto {
  @IsString()
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
  condition!: string;

  @IsEnum(['allow', 'allow_with_flag', 'quarantine', 'reject', 'escalate', 'report_to_authorities'])
  action!: string;

  @IsOptional()
  @IsEnum(['low', 'normal', 'high', 'urgent', 'critical'])
  priority?: string;

  @IsOptional()
  @IsString()
  createdBy?: string;
}

export class ToggleRuleDto {
  @IsString()
  ruleId!: string;

  @IsBoolean()
  isActive!: boolean;

  @IsString()
  userId!: string;
}
