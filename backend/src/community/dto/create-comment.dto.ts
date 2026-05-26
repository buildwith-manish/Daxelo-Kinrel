import { IsString, IsOptional, Length } from 'class-validator';

export class CreateCommentDto {
  @IsString()
  @Length(1, 2000)
  body!: string;

  @IsOptional()
  @IsString()
  parentId?: string;
}
