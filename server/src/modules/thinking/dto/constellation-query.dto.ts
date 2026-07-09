import { IsOptional, IsString } from 'class-validator';

export class ConstellationQueryDto {
  @IsString()
  @IsOptional()
  familyId?: string;
}
