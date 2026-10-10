// server/src/modules/chat/cloud-backups.controller.ts
//
// DAXELO KINREL — Tier 5 Feature 5.5: Cloud backup — Controller

import { Body, Controller, Delete, Get, Param, Post, Query, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { CloudBackupsService } from './cloud-backups.service';

@Controller('chat/backups')
@UseGuards(JwtAuthGuard)
export class CloudBackupsController {
  constructor(private readonly service: CloudBackupsService) {}

  /// POST /chat/backups
  /// Record a backup the Flutter client just completed.
  @Post()
  async record(
    @CurrentUser('id') userId: string,
    @Body() body: {
      provider: 'google_drive' | 'icloud';
      backupKey: string;
      sizeBytes: number;
      messageCount?: number;
      mediaCount?: number;
      deviceLabel?: string | null;
      fileId?: string | null;
    },
  ) {
    return this.service.recordBackup(userId, body);
  }

  /// GET /chat/backups?limit=20
  /// List the caller's recent backups.
  @Get()
  async list(@CurrentUser('id') userId: string, @Query('limit') limit?: string) {
    return this.service.listMyBackups(userId, limit ? parseInt(limit, 10) : 20);
  }

  /// GET /chat/backups/latest
  /// Get the most recent backup (for the "Last backup: X ago" label).
  @Get('latest')
  async latest(@CurrentUser('id') userId: string) {
    return this.service.getLatestBackup(userId);
  }

  /// DELETE /chat/backups/:id
  /// Delete a backup record (cloud-side deletion is the client's job).
  @Delete(':id')
  async delete(@CurrentUser('id') userId: string, @Param('id') id: string) {
    return this.service.deleteBackup(userId, id);
  }
}
