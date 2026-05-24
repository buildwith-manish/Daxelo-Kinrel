import { IsOptional, IsString, IsInt, Min, Max, IsIn } from 'class-validator';
import { Type } from 'class-transformer';

/**
 * DTO for GET /api/v1/graph/:familyId (unified — path mode or tree mode)
 *
 * Path mode:  provide `from` + `to`
 * Tree mode:  provide `root` + `depth` + `format` + `locale`
 */
export class GraphQueryDto {
  // ── Path mode params ──────────────────────────────────────────────
  @IsOptional()
  @IsString()
  from?: string;

  @IsOptional()
  @IsString()
  to?: string;

  // ── Tree mode params ──────────────────────────────────────────────
  @IsOptional()
  @IsString()
  root?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(10)
  depth?: number;

  @IsOptional()
  @IsIn(['nested', 'flat'])
  format?: 'nested' | 'flat';

  @IsOptional()
  @IsString()
  locale?: string;
}

/**
 * DTO for GET /api/v1/graph/:familyId/tree
 */
export class TreeQueryDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(10)
  depth?: number;

  @IsOptional()
  @IsString()
  includeDeceased?: string; // 'true' | 'false'

  @IsOptional()
  @IsIn(['nested', 'flat'])
  format?: 'nested' | 'flat';
}

/**
 * DTO for GET /api/v1/graph/:familyId/path
 */
export class PathQueryDto {
  @IsString()
  from!: string;

  @IsString()
  to!: string;
}
