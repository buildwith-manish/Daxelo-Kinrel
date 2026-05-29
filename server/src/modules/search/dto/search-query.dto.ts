import {
  IsString,
  IsOptional,
  IsEnum,
  IsInt,
  Min,
  Max,
  MaxLength,
  MinLength,
} from 'class-validator';
import { Transform, Type } from 'class-transformer';

/**
 * SearchType — Types of entities that can be searched.
 */
export enum SearchType {
  ALL = 'all',
  USERS = 'users',
  FAMILIES = 'families',
}

/**
 * SearchQueryDto — Validated query parameters for the unified search endpoint.
 *
 * GET /api/search?q=query&type=all|users|families&limit=20&offset=0
 */
export class SearchQueryDto {
  /**
   * Search query string.
   * Minimum 1 character, maximum 100 characters.
   */
  @IsString()
  @MinLength(1)
  @MaxLength(100)
  q!: string;

  /**
   * Type of entities to search.
   * Defaults to 'all' (search both users and families).
   */
  @IsOptional()
  @IsEnum(SearchType)
  type?: SearchType = SearchType.ALL;

  /**
   * Maximum number of results to return.
   * Between 1 and 50, defaults to 20.
   */
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(50)
  limit?: number = 20;

  /**
   * Number of results to skip (for pagination).
   * Minimum 0, defaults to 0.
   */
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  offset?: number = 0;
}
