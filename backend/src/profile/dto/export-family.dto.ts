import { IsString, IsOptional, IsIn } from 'class-validator';

export class ExportFamilyDto {
  @IsIn(['pdf', 'json', 'csv'])
  format: string;
}
