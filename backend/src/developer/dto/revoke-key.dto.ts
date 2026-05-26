import { IsString, Length } from 'class-validator';

export class RevokeKeyDto {
  @IsString()
  @Length(1, 500)
  reason!: string;
}
