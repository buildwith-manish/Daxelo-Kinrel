import { IsString, IsNotEmpty, IsOptional, IsIn, MaxLength, IsArray } from 'class-validator';

export class CreateTicketDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(200)
  subject!: string;

  @IsString()
  @IsNotEmpty()
  @MaxLength(5000)
  description!: string;

  @IsOptional()
  @IsIn(['bug', 'feature', 'account', 'billing', 'other'])
  category?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  subcategory?: string;

  @IsOptional()
  @IsIn(['low', 'medium', 'high', 'critical'])
  severity?: string;

  @IsOptional()
  @IsArray()
  attachments?: string[];

  @IsOptional()
  @IsString()
  @MaxLength(50)
  appVersion?: string;

  @IsOptional()
  @IsString()
  @MaxLength(50)
  platform?: string;

  @IsOptional()
  @IsString()
  @MaxLength(500)
  deviceInfo?: string;

  @IsOptional()
  @IsString()
  @MaxLength(10)
  language?: string;
}
