import { IsString, MinLength, MaxLength } from 'class-validator';

export class Setup2faDto {
  // No fields needed for setup - just returns secret + QR URL
}

export class Verify2faDto {
  @IsString()
  @MinLength(6)
  @MaxLength(6)
  code: string;
}

export class Disable2faDto {
  @IsString()
  password: string;
}
