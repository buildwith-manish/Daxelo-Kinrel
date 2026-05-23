import { IsString, IsOptional, IsEnum } from 'class-validator';

export class CreateInvitationDto {
  @IsString()
  familyId!: string;

  @IsString()
  inviterId!: string;

  @IsOptional()
  @IsString()
  recipientEmail?: string;

  @IsOptional()
  @IsString()
  recipientPhone?: string;

  @IsOptional()
  @IsString()
  recipientName?: string;

  @IsOptional()
  @IsEnum(['admin', 'editor', 'member', 'viewer'])
  role?: string;

  @IsOptional()
  @IsEnum(['email', 'whatsapp', 'direct_link'])
  channel?: string;

  @IsOptional()
  preFilledData?: Record<string, unknown>;
}
