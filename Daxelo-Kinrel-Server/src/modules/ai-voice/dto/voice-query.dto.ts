import { IsString, IsOptional } from 'class-validator';

export class VoiceQueryDto {
  @IsString()
  audio!: string;

  @IsOptional()
  @IsString()
  language?: string;
}
