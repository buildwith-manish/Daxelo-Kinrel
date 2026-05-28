import { IsString, IsUrl } from 'class-validator';

export class UpdateAvatarDto {
  @IsString()
  @IsUrl()
  imageUrl: string;
}
