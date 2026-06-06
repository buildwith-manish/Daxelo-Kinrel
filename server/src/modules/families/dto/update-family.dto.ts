import { PartialType } from '@nestjs/mapped-types';
import { CreateFamilyDto } from './create-family.dto';
import { IsOptional, IsString, IsUrl, MaxLength } from 'class-validator';

export class UpdateFamilyDto extends PartialType(CreateFamilyDto) {
  @IsOptional()
  @IsString()
  @MaxLength(30)
  username?: string;

  @IsOptional()
  @IsUrl()
  avatarUrl?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  region?: string;
}
