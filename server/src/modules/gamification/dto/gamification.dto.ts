import { IsOptional, IsString, IsInt, IsIn, IsNumber, Min, Max } from 'class-validator';
import { Type } from 'class-transformer';
import { ApiPropertyOptional, ApiProperty } from '@nestjs/swagger';

export class LeaderboardQueryDto {
  @ApiPropertyOptional({ description: 'Filter by family ID' })
  @IsOptional()
  @IsString()
  familyId?: string;

  @ApiPropertyOptional({
    description: 'Timeframe filter',
    enum: ['weekly', 'monthly', 'all'],
    default: 'all',
  })
  @IsOptional()
  @IsIn(['weekly', 'monthly', 'all'])
  timeframe?: 'weekly' | 'monthly' | 'all' = 'all';

  @ApiPropertyOptional({ description: 'Page number', default: 1 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number = 1;

  @ApiPropertyOptional({ description: 'Items per page', default: 20 })
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number = 20;
}

export class CheckInDto {
  @ApiProperty({ description: 'Family ID for the check-in' })
  @IsString()
  familyId!: string;
}

export class SubmitDailyChallengeDto {
  @ApiProperty({ description: 'Index of the selected answer option' })
  @IsNumber()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  answer!: number;
}

export class ContributionQueryDto {
  @ApiProperty({ description: 'Family ID to get contributions for' })
  @IsString()
  familyId!: string;
}
