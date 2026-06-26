import { IsOptional, IsString, IsEmail, IsPhoneNumber } from 'class-validator';

/**
 * DTO for `POST /families/:familyId/persons/:personId/invite`.
 *
 * Either `recipientEmail` or `recipientPhone` must be provided. The
 * `recipientName` is optional but useful for tracking the invitation
 * before it is accepted.
 */
export class InvitePersonDto {
  @IsOptional()
  @IsString()
  recipientName?: string;

  @IsOptional()
  @IsEmail()
  recipientEmail?: string;

  @IsOptional()
  @IsString()
  recipientPhone?: string;

  @IsOptional()
  @IsString()
  role?: string; // role in the family: member | admin | editor | viewer
}
