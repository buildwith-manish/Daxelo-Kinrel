import { PartialType } from '@nestjs/mapped-types';
import { CreateFamilyDto } from './create-family.dto';
import { IsBoolean, IsOptional, IsString } from 'class-validator';

export class UpdateFamilyDto extends PartialType(CreateFamilyDto) {
  @IsOptional()
  @IsString()
  username?: string;

  @IsOptional()
  @IsString()
  avatarUrl?: string;

  @IsOptional()
  @IsString()
  region?: string;

  // P1.4: Bridge role opt-in for silent check-in alerts.
  @IsOptional()
  @IsBoolean()
  bridgeRoleOptIn?: boolean;
}
