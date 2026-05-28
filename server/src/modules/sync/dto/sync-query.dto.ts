import { IsDateString, IsString, IsOptional } from 'class-validator';

/**
 * SyncQueryDto — Request body for the POST /api/sync endpoint.
 *
 * The client sends the timestamp of its last successful sync
 * and receives all data modified since that point.
 */
export class SyncQueryDto {
  /**
   * ISO 8601 timestamp — only records with updatedAt > since will be returned.
   * If omitted, the server returns all data (first sync).
   */
  @IsOptional()
  @IsDateString()
  since?: string;

  /**
   * User ID requesting the sync.
   * Must match the authenticated user's ID (enforced by controller).
   */
  @IsString()
  userId: string;
}
