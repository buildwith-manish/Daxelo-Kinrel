import { IsString, IsBoolean, IsOptional, Matches } from 'class-validator';

export class QuietHoursDto {
  @IsString()
  @Matches(/^([01]\d|2[0-3]):([0-5]\d)$/, { message: 'Start must be in HH:MM format' })
  start: string;

  @IsString()
  @Matches(/^([01]\d|2[0-3]):([0-5]\d)$/, { message: 'End must be in HH:MM format' })
  end: string;

  @IsBoolean()
  enabled: boolean;
}
