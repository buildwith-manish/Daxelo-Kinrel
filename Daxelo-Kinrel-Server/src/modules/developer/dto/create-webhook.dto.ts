import { IsString, IsArray, IsOptional, IsUrl, MaxLength, MinLength } from 'class-validator';

export class CreateWebhookDto {
  @IsString()
  @IsUrl()
  url!: string;

  @IsArray()
  @IsString({ each: true })
  events!: string[];

  @IsOptional()
  @IsString()
  @MaxLength(500)
  description?: string;

  @IsOptional()
  @IsString()
  @MinLength(16)
  @MaxLength(128)
  secret?: string;
}
