import { IsString, IsNotEmpty, MaxLength } from 'class-validator';

export class AddMessageDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(5000)
  content!: string;
}
