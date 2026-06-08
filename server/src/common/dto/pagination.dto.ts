import { IsOptional, IsInt, IsString, IsIn, Min, Max } from 'class-validator';
import { Transform, Type } from 'class-transformer';

// Common sort fields that are safe to use with Prisma orderBy
export const SAFE_SORT_FIELDS = [
  'createdAt',
  'updatedAt',
  'name',
  'email',
  'id',
  'startDate',
  'expiresAt',
  'joinedAt',
] as const;

export type SafeSortField = typeof SAFE_SORT_FIELDS[number];

export class PaginationDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  page?: number = 1;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number = 20;

  @IsOptional()
  @IsString()
  sort?: string = 'createdAt';

  @IsOptional()
  @IsIn(['asc', 'desc'])
  @Transform(({ value }) => (typeof value === 'string' ? value.toLowerCase() : value))
  order?: 'asc' | 'desc' = 'desc';
}

/**
 * Helper to convert PaginationDto to Prisma skip/take args.
 * Sanitizes the sort field against a whitelist to prevent field injection.
 */
export function paginationToPrisma(dto: PaginationDto, allowedSortFields?: string[]) {
  const page = dto.page ?? 1;
  const limit = dto.limit ?? 20;
  const skip = (page - 1) * limit;

  // Sanitize sort field — only allow known safe fields
  const sortField = dto.sort || 'createdAt';
  const safeFields: readonly string[] = allowedSortFields ?? SAFE_SORT_FIELDS;
  const safeSort = safeFields.includes(sortField) ? sortField : 'createdAt';

  return {
    skip,
    take: limit,
    orderBy: {
      [safeSort]: dto.order || 'desc',
    },
  };
}
