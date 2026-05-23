import {
  IsString,
  IsOptional,
  IsArray,
  IsBoolean,
  IsEnum,
} from 'class-validator';

export class OptInDto {
  @IsString()
  userId!: string;

  @IsString()
  phone!: string;

  @IsEnum(['app_settings', 'onboarding', 'invite_flow', 'customer_service'])
  optInMethod!: string;

  @IsArray()
  @IsString({ each: true })
  categories!: string[];

  @IsBoolean()
  marketingConsent: boolean = false;
}

export class OptOutDto {
  @IsString()
  userId!: string;

  @IsEnum(['whatsapp_stop', 'app_settings', 'account_deletion'])
  optOutMethod!: string;

  @IsOptional()
  @IsString()
  reason?: string;
}

export class MarketingToggleDto {
  @IsString()
  userId!: string;

  @IsBoolean()
  marketingConsent!: boolean;

  @IsString()
  method!: string;
}
