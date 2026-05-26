import { IsString, IsArray, ArrayMinSize, IsOptional, IsIn, Length } from 'class-validator';

const VALID_TIERS = ['free', 'pro', 'enterprise'] as const;

export class CreateKeyDto {
  @IsString()
  @Length(1, 100)
  name!: string;

  @IsArray()
  @ArrayMinSize(1)
  @IsString({ each: true })
  scopes!: string[];

  @IsOptional()
  @IsIn(VALID_TIERS)
  tier?: string = 'free';
}
