import { IsNotEmpty, IsString } from 'class-validator';

export class SendTapDto {
  @IsString()
  @IsNotEmpty()
  receiverId: string;

  @IsString()
  @IsNotEmpty()
  familyId: string;
}
