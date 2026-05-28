import { Controller, Post, Body, UseGuards, HttpCode, HttpStatus, Logger } from '@nestjs/common';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { SyncService } from './sync.service';
import { SyncQueryDto } from './dto/sync-query.dto';

/**
 * SyncController — Handles incremental data synchronization.
 *
 * POST /api/sync
 * Body: { since: ISO timestamp, userId: string }
 * Auth: required (JWT guard)
 *
 * Returns all data modified after the `since` timestamp,
 * enabling offline-capable clients to stay in sync.
 */
@Controller('sync')
@UseGuards(JwtAuthGuard)
export class SyncController {
  private readonly logger = new Logger(SyncController.name);

  constructor(private readonly syncService: SyncService) {}

  @Post()
  @HttpCode(HttpStatus.OK)
  async sync(
    @CurrentUser('id') authenticatedUserId: string,
    @Body() dto: SyncQueryDto,
  ) {
    // Security: ensure the userId in the body matches the authenticated user
    if (dto.userId && dto.userId !== authenticatedUserId) {
      dto.userId = authenticatedUserId;
    }

    this.logger.debug(`Sync requested by user ${authenticatedUserId} since ${dto.since ?? 'epoch'}`);

    return this.syncService.sync(dto.since, authenticatedUserId);
  }
}
