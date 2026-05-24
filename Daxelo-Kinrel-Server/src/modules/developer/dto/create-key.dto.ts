import { IsString, IsArray, IsEnum, IsOptional, MaxLength, MinLength } from 'class-validator';

export class CreateKeyDto {
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  name!: string;

  @IsArray()
  @IsString({ each: true })
  scopes!: string[];

  @IsOptional()
  @IsEnum(['free', 'pro', 'enterprise'])
  tier?: string;
}

export class RevokeKeyDto {
  @IsString()
  @MinLength(1)
  keyId!: string;

  @IsOptional()
  @IsString()
  @MinLength(1)
  @MaxLength(500)
  reason?: string;
}
