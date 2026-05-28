import { IsString, IsOptional, IsInt, IsBoolean, IsNotEmpty, MaxLength } from 'class-validator';

export class AddPersonDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(100)
  name!: string;

  @IsString()
  @IsOptional()
  gender?: string;

  @IsInt()
  @IsOptional()
  birthYear?: number;

  @IsBoolean()
  @IsOptional()
  isAnchor?: boolean;

  @IsString()
  @IsOptional()
  city?: string;

  @IsString()
  @IsOptional()
  gotra?: string;

  @IsString()
  @IsOptional()
  occupation?: string;

  @IsString()
  @IsOptional()
  @MaxLength(500)
  notes?: string;

  @IsString()
  @IsOptional()
  sideOfFamily?: string;

  @IsString()
  @IsOptional()
  photoUrl?: string;

  @IsString()
  @IsOptional()
  dateOfBirth?: string;
}
