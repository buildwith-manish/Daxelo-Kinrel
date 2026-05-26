import { IsString, IsBoolean } from 'class-validator';

export class FeedbackDto {
  @IsString()
  slug!: string;

  @IsBoolean()
  helpful!: boolean;
}
