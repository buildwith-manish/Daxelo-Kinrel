import { IsString, IsOptional, IsIn, IsArray, MaxLength, MinLength } from 'class-validator';

export class CreateTicketDto {
  @IsIn([
    'billing', 'account', 'data_loss', 'bug', 'feature_request',
    'general', 'matrimonial', 'verification', 'privacy',
  ])
  category!: string;

  @IsOptional()
  @IsString()
  subcategory?: string;

  @IsIn(['critical', 'high', 'medium', 'low'])
  severity!: string;

  @IsString()
  @MinLength(5)
  @MaxLength(255)
  subject!: string;

  @IsString()
  @MinLength(10)
  description!: string;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  attachments?: string[];

  @IsOptional()
  @IsString()
  appVersion?: string;

  @IsOptional()
  @IsIn(['android', 'ios', 'web'])
  platform?: string;

  @IsOptional()
  @IsString()
  deviceInfo?: string;
}
