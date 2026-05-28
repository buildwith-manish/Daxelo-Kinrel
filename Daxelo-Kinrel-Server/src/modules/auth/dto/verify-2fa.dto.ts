import { IsString, MinLength, IsNotEmpty } from 'class-validator';

export class Verify2FADto {
  @IsString()
  @IsNotEmpty({ message: '2FA code is required' })
  @MinLength(6, { message: '2FA code must be at least 6 characters' })
  code!: string;
}

export class Disable2FADto {
  @IsString()
  @IsNotEmpty({ message: 'Password is required to disable 2FA' })
  password!: string;
}
