import { IsString } from 'class-validator';

export class LinkGoogleDto {
  @IsString()
  googleToken: string;
}
