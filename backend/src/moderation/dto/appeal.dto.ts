import { IsString, Length } from 'class-validator';

export class AppealDto {
  @IsString()
  caseId!: string;

  @IsString()
  appellantId!: string;

  @IsString()
  @Length(10, 2000)
  appealReason!: string;
}
