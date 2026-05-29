import { IsOptional, IsInt, IsString, IsIn, Min, Max } from 'class-validator';
import { Transform, Type } from 'class-transformer';

/**
 * PaginationDto — Reusable DTO for paginated endpoints.
 *
 * Provides page-based or offset-based pagination with sorting.
 *
 * Fields:
 *  - page:   Page number (1-based), defaults to 1
 *  - limit:  Items per page, defaults to 20, max 100
 *  - sort:   Field name to sort by (default varies by endpoint)
 *  - order:  Sort direction — 'asc' or 'desc', defaults to 'desc'
 */
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
 */
export function paginationToPrisma(dto: PaginationDto) {
  const page = dto.page ?? 1;
  const limit = dto.limit ?? 20;
  const skip = (page - 1) * limit;
  return {
    skip,
    take: limit,
    orderBy: {
      [dto.sort || 'createdAt']: dto.order || 'desc',
    },
  };
}
