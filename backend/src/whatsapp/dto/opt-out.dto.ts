import { IsString, IsOptional, IsIn } from 'class-validator';

export class OptOutDto {
  @IsString()
  userId!: string;

  @IsIn(['whatsapp_stop', 'app_settings', 'account_deletion'])
  optOutMethod!: string;

  @IsOptional()
  @IsString()
  reason?: string;
}
