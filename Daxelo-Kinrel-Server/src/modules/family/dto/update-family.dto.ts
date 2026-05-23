import {
  IsString,
  IsOptional,
  MaxLength,
} from 'class-validator';

export class UpdateFamilyDto {
  @IsOptional()
  @IsString()
  @MaxLength(200, { message: 'Family name must not exceed 200 characters' })
  name?: string;

  @IsOptional()
  @IsString()
  @MaxLength(1000, { message: 'Description must not exceed 1000 characters' })
  description?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(10, { message: 'Language code must not exceed 10 characters' })
  primaryLanguage?: string;

  @IsOptional()
  @IsString()
  @MaxLength(100, { message: 'Gotra must not exceed 100 characters' })
  gotra?: string | null;

  @IsOptional()
  @IsString()
  @MaxLength(200, { message: 'Origin village must not exceed 200 characters' })
  originVillage?: string | null;
}
