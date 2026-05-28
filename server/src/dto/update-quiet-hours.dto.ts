import { IsString, IsOptional } from 'class-validator';

export class UpdateQuietHoursDto {
  @IsString()
  @IsOptional()
  start?: string;

  @IsString()
  @IsOptional()
  end?: string;

  @IsString()
  @IsOptional()
  timezone?: string;
}
