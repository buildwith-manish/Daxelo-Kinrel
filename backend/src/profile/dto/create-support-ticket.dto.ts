import { IsString, IsOptional, IsUrl, MaxLength } from 'class-validator';

export class CreateSupportTicketDto {
  @IsString()
  @MaxLength(255)
  subject: string;

  @IsString()
  @MaxLength(5000)
  message: string;

  @IsOptional()
  @IsUrl()
  screenshotUrl?: string;

  @IsOptional()
  @IsString()
  type?: string;

  @IsOptional()
  @IsString()
  deviceInfo?: string;
}
