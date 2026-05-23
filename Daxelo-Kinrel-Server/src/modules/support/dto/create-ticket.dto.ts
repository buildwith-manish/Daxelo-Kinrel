import {
  IsEnum,
  IsString,
  IsOptional,
  IsArray,
  IsUrl,
  MaxLength,
  MinLength,
} from 'class-validator';

export class CreateTicketDto {
  @IsEnum([
    'billing',
    'account',
    'data_loss',
    'bug',
    'feature_request',
    'general',
    'matrimonial',
    'verification',
    'privacy',
  ])
  category!: string;

  @IsOptional()
  @IsString()
  subcategory?: string;

  @IsEnum(['critical', 'high', 'medium', 'low'])
  severity: string = 'medium';

  @IsString()
  @MinLength(5)
  @MaxLength(255)
  subject!: string;

  @IsString()
  @MinLength(10)
  description!: string;

  @IsOptional()
  @IsArray()
  @IsUrl({}, { each: true })
  attachments?: string[];

  @IsOptional()
  @IsString()
  appVersion?: string;

  @IsOptional()
  @IsEnum(['android', 'ios', 'web'])
  platform?: string;

  @IsOptional()
  @IsString()
  deviceInfo?: string;
}
