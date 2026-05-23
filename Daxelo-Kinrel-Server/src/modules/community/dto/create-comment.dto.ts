import { IsString, IsOptional, MaxLength, MinLength } from 'class-validator';

export class CreateCommentDto {
  @IsString()
  authorId!: string;

  @IsOptional()
  @IsString()
  parentId?: string;

  @IsString()
  @MinLength(1)
  @MaxLength(2000)
  body!: string;
}
