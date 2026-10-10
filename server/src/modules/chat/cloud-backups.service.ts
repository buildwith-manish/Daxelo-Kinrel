// server/src/modules/chat/cloud-backups.service.ts
//
// DAXELO KINREL — Tier 5 Feature 5.5: Cloud backup — Service
//
// Records cloud backup metadata so the user can restore on a new device.
// The actual upload happens Flutter-side (using googleapis for Google
// Drive + a native plugin for iCloud). The server just records the
// metadata + the denormalized lastCloudBackupAt cache on User.

import { Injectable, BadRequestException, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class CloudBackupsService {
  private readonly logger = new Logger(CloudBackupsService.name);

  constructor(private readonly prisma: PrismaService) {}

  /// Record a backup the Flutter client just completed. Updates the
  /// denormalized lastCloudBackupAt cache on the User row.
  async recordBackup(
    userId: string,
    params: {
      provider: 'google_drive' | 'icloud';
      backupKey: string;
      sizeBytes: number;
      messageCount?: number;
      mediaCount?: number;
      deviceLabel?: string | null;
      fileId?: string | null;
    },
  ) {
    if (!['google_drive', 'icloud'].includes(params.provider)) {
      throw new BadRequestException('provider must be google_drive or icloud');
    }
    if (!params.backupKey?.trim()) {
      throw new BadRequestException('backupKey is required');
    }
    if (params.sizeBytes < 0) {
      throw new BadRequestException('sizeBytes must be >= 0');
    }

    const id = `cbr_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
    const record = await this.prisma.cloudBackupRecord.create({
      data: {
        id,
        userId,
        provider: params.provider,
        backupKey: params.backupKey,
        sizeBytes: BigInt(params.sizeBytes),
        messageCount: params.messageCount ?? 0,
        mediaCount: params.mediaCount ?? 0,
        deviceLabel: params.deviceLabel ?? null,
        fileId: params.fileId ?? null,
      },
    });

    // Update the denormalized cache.
    await this.prisma.user.update({
      where: { id: userId },
      data: { lastCloudBackupAt: new Date() },
    });

    return record;
  }

  /// List the caller's recent backups (for the restore picker).
  async listMyBackups(userId: string, limit: number = 20) {
    return this.prisma.cloudBackupRecord.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
      take: Math.min(limit, 50),
    });
  }

  /// Get the most recent backup (for the "Last backup: 2 hours ago" label).
  async getLatestBackup(userId: string) {
    return this.prisma.cloudBackupRecord.findFirst({
      where: { userId },
      orderBy: { createdAt: 'desc' },
    });
  }

  /// Delete a backup record (the actual cloud-side deletion is the
  /// Flutter client's responsibility via the provider's API).
  async deleteBackup(userId: string, backupId: string) {
    const existing = await this.prisma.cloudBackupRecord.findUnique({
      where: { id: backupId },
    });
    if (!existing) return { success: false, error: 'not_found' };
    if (existing.userId !== userId) return { success: false, error: 'not_owner' };
    await this.prisma.cloudBackupRecord.delete({ where: { id: backupId } });
    return { success: true, deleted: backupId };
  }
}
