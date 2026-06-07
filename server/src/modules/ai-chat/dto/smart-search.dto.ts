import { IsString, IsOptional, MaxLength } from 'class-validator';

export class SmartSearchDto {
  @IsString()
  @MaxLength(100)
  query!: string;

  @IsString()
  @MaxLength(50)
  familyId!: string;

  @IsOptional()
  @IsString()
  @MaxLength(10)
  language?: string;
}
