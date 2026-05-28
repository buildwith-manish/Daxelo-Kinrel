import { IsOptional, IsString } from 'class-validator';

export class GenerateReferralDto {
  @IsOptional()
  @IsString()
  userId?: string;
}

export class ApplyReferralDto {
  @IsString()
  code!: string;

  @IsOptional()
  @IsString()
  userId?: string;
}
