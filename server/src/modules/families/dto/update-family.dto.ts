import { PartialType } from '@nestjs/mapped-types';
import { CreateFamilyDto } from './create-family.dto';
import { IsOptional, IsString } from 'class-validator';

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
}
