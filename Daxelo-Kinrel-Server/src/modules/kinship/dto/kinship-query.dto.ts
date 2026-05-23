import { IsOptional, IsString, IsIn } from 'class-validator';

export class KinshipQueryDto {
  @IsOptional()
  @IsString()
  key?: string;

  @IsOptional()
  @IsString()
  lang?: string;

  @IsOptional()
  @IsString()
  q?: string;

  @IsOptional()
  @IsString()
  category?: string;

  @IsOptional()
  @IsIn(['male', 'female', 'neutral'], {
    message: 'Gender must be one of: male, female, neutral',
  })
  gender?: 'male' | 'female' | 'neutral';

  @IsOptional()
  @IsString()
  lineage?: string;
}
