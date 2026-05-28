import { IsString, IsOptional } from 'class-validator';

export class TranscribeDto {
  @IsString()
  audio!: string; // base64 encoded audio

  @IsOptional()
  @IsString()
  language?: string;
}

export class VoiceLookupDto {
  @IsString()
  audio!: string; // base64 encoded audio

  @IsOptional()
  @IsString()
  language?: string;
}
