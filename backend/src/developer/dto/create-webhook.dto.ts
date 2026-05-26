import { IsString, IsArray, ArrayMinSize, IsOptional, Length, IsUrl } from 'class-validator';

export class CreateWebhookDto {
  @IsUrl()
  url!: string;

  @IsArray()
  @ArrayMinSize(1)
  @IsString({ each: true })
  events!: string[];

  @IsOptional()
  @IsString()
  @Length(0, 500)
  description?: string;
}
