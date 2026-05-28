import { IsString, IsOptional, IsIn } from 'class-validator';

export class CreateSessionDto {
  @IsOptional()
  @IsString()
  deviceName?: string;

  @IsOptional()
  @IsIn(['mobile', 'desktop', 'web'])
  deviceType?: string;

  @IsOptional()
  @IsString()
  ipAddress?: string;

  @IsOptional()
  @IsString()
  location?: string;
}
