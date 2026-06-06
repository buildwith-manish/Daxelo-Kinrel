import { IsString, IsNotEmpty, MaxLength } from 'class-validator';

export class RemoveFcmTokenDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(512)
  token!: string;
}
