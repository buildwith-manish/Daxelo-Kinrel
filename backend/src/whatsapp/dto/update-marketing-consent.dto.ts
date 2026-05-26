import { IsString, IsBoolean } from 'class-validator';

export class UpdateMarketingConsentDto {
  @IsString()
  userId!: string;

  @IsBoolean()
  marketingConsent!: boolean;

  @IsString()
  method!: string;
}
