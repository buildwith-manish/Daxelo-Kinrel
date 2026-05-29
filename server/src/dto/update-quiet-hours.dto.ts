import { IsString, IsOptional, MaxLength } from 'class-validator';

export class UpdateQuietHoursDto {
  @IsString()
  @IsOptional()
  @MaxLength(10)
  start?: string;

  @IsString()
  @IsOptional()
  @MaxLength(10)
  end?: string;

  @IsString()
  @IsOptional()
  @MaxLength(50)
  timezone?: string;
}
