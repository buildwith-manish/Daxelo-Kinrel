import { IsString, IsOptional, IsIn, IsArray, IsBoolean } from 'class-validator';

export class OptInDto {
  @IsString()
  userId!: string;

  @IsString()
  phone!: string;

  @IsIn(['app_settings', 'onboarding', 'invite_flow', 'customer_service'])
  optInMethod!: string;

  @IsArray()
  @IsString({ each: true })
  categories!: string[];

  @IsOptional()
  @IsBoolean()
  marketingConsent?: boolean;
}
