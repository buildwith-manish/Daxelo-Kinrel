import { IsString, IsNotEmpty, IsOptional, IsEmail, IsIn, MaxLength, IsUUID } from 'class-validator';

export class CreateInvitationDto {
  @IsUUID()
  @IsNotEmpty()
  familyId!: string;

  @IsOptional()
  @IsEmail()
  @MaxLength(255)
  recipientEmail?: string;

  @IsOptional()
  @IsString()
  @MaxLength(30)
  recipientPhone?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  recipientName?: string;

  @IsOptional()
  @IsIn(['admin', 'editor', 'member', 'viewer'])
  role?: string;

  @IsOptional()
  @IsIn(['email', 'whatsapp', 'direct_link'])
  channel?: string;
}
