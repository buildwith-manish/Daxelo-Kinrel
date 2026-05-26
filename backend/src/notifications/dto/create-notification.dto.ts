import { IsString, IsOptional, IsIn, IsObject } from 'class-validator';

export class CreateNotificationDto {
  @IsString()
  type!: string;

  @IsString()
  actorUserId!: string;

  @IsString()
  targetUserId!: string;

  @IsOptional()
  @IsString()
  familyId?: string;

  @IsOptional()
  @IsString()
  personId?: string;

  @IsObject()
  payload!: Record<string, unknown>;

  @IsIn(['critical', 'high', 'normal', 'low'])
  priority!: 'critical' | 'high' | 'normal' | 'low';
}
