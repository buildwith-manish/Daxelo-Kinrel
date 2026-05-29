import { IsString, IsOptional } from 'class-validator';

export class SmartSearchDto {
  @IsString()
  query!: string;

  @IsString()
  familyId!: string;

  @IsOptional()
  @IsString()
  language?: string;
}
