import { IsOptional, IsString, IsNotEmpty, MaxLength } from 'class-validator';

export class GenerateReferralDto {
  @IsOptional()
  @IsString()
  userId?: string;
}

export class ApplyReferralDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(50)
  code!: string;

  @IsOptional()
  @IsString()
  userId?: string;
}
