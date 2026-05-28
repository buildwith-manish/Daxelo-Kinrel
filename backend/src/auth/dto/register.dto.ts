import { IsEmail, IsString, MinLength, MaxLength, IsOptional, Length } from 'class-validator';

export class RegisterDto {
  @IsString()
  @MinLength(2)
  @MaxLength(100)
  name: string;

  @IsEmail()
  email: string;

  @IsString()
  @MinLength(8)
  @MaxLength(100)
  password: string;

  @IsOptional()
  @IsString()
  @Length(8, 8)
  referralCode?: string;
}
