import { IsString } from 'class-validator';

export class GenerateReferralDto {
  @IsString()
  userId!: string;
}

export class ApplyReferralDto {
  @IsString()
  code!: string;

  @IsString()
  userId!: string;
}
