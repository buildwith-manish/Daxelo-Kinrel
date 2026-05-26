import { IsString, IsOptional, IsIn, IsObject } from 'class-validator';

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
  @IsIn(['admin', 'editor', 'member', 'viewer'])
  role?: 'admin' | 'editor' | 'member' | 'viewer';

  @IsOptional()
  @IsIn(['email', 'whatsapp', 'direct_link'])
  channel?: 'email' | 'whatsapp' | 'direct_link';

  @IsOptional()
  @IsObject()
  preFilledData?: Record<string, unknown>;
}
