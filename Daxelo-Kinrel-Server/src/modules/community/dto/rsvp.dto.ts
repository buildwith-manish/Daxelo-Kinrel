import { IsString, IsEnum, IsOptional, IsBoolean } from 'class-validator';

export class RsvpDto {
  @IsString()
  userId!: string;

  @IsEnum(['pending', 'attending', 'maybe', 'declined'])
  status!: string;

  @IsOptional()
  @IsBoolean()
  plusOne?: boolean;

  @IsOptional()
  @IsString()
  note?: string;
}
