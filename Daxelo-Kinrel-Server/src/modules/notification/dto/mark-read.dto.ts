import { IsString, IsOptional, IsArray } from 'class-validator';

/**
 * DTO for PATCH /api/notifications — Mark as read
 */
export class MarkReadDto {
  @IsString()
  userId!: string;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  notificationIds?: string[];
}
