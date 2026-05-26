import { IsString, IsOptional } from 'class-validator';

export class GetInvitationsDto {
  @IsString()
  familyId!: string;

  @IsOptional()
  @IsString()
  status?: string;
}
