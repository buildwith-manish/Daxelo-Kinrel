import { IsString, IsOptional, MaxLength } from 'class-validator';

export class TranscribeDto {
  @IsString()
  @MaxLength(10_000_000) // base64 encoded audio can be large
  audio!: string; // base64 encoded audio

  @IsOptional()
  @IsString()
  @MaxLength(10)
  language?: string;
}

export class VoiceLookupDto {
  @IsString()
  @MaxLength(10_000_000) // base64 encoded audio can be large
  audio!: string; // base64 encoded audio

  @IsOptional()
  @IsString()
  @MaxLength(10)
  language?: string;
}
