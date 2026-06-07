import { IsString, IsNotEmpty, IsIn, MaxLength } from 'class-validator';

export class RegisterFcmTokenDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(512)
  token!: string;

  @IsString()
  @IsIn(['ios', 'android', 'web'])
  deviceType!: string;
}
