import { IsString, IsOptional, Length } from 'class-validator';

export class ClassifyContentDto {
  @IsString()
  @Length(1, 100)
  contentType!: string;

  @IsString()
  contentId!: string;

  @IsOptional()
  @IsString()
  contentPreview?: string;

  @IsOptional()
  @IsString()
  authorId?: string;

  @IsOptional()
  @IsString()
  familyId?: string;
}
