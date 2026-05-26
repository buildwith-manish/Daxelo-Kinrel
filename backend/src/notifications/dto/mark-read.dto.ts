import { IsString, IsOptional, IsArray } from 'class-validator';

export class MarkReadDto {
  @IsString()
  userId!: string;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  notificationIds?: string[];
}
