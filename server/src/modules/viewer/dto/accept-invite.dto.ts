import { IsString, IsNotEmpty, MaxLength } from 'class-validator';

/**
 * DTO for `POST /families/:familyId/invitations/:code/accept`.
 *
 * Accepts an outstanding person-link invitation and binds the
 * authenticated user to the target Person node.
 */
export class AcceptInviteDto {
  /** Optional display name the user wants to override on the Person node. */
  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  displayName?: string;
}
