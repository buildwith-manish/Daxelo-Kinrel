import { ApiProperty, ApiPropertyOptional } from '@nestjs/swagger';
import { IsOptional, IsString, IsIn, IsInt, Min, Max } from 'class-validator';
import { Type } from 'class-transformer';

export class FollowUserDto {
  @ApiProperty({ description: 'ID of the user to follow' })
  @IsString()
  userId!: string;
}

export class FollowStatusQueryDto {
  @ApiProperty({ description: 'ID of the target user' })
  @IsString()
  userId!: string;
}

export class FollowPaginationDto {
  @ApiPropertyOptional({ default: 1 })
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) page?: number = 1;

  @ApiPropertyOptional({ default: 20 })
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(100) limit?: number = 20;
}
