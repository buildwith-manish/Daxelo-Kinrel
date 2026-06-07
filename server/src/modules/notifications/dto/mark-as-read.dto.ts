import { IsArray, IsString, ArrayMaxSize } from 'class-validator';

export class MarkAsReadDto {
  @IsArray()
  @IsString({ each: true })
  @ArrayMaxSize(100)
  notificationIds!: string[];
}
