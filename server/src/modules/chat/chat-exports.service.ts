// server/src/modules/chat/chat-exports.service.ts
//
// DAXELO KINREL — Tier 5 Feature 5.4: Chat export — Service
//
// Job-creation + status-polling for chat exports. The actual file-building
// (SELECTing messages, formatting as text or zipping media, uploading to
// storage, emailing the user) is a follow-up ChatExportRunner that
// processes pending jobs. This service is the user-facing layer.

import { Injectable, BadRequestException, NotFoundException, ForbiddenException, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class ChatExportsService {
  private readonly logger = new Logger(ChatExportsService.name);

  constructor(private readonly prisma: PrismaService) {}

  /// Create a chat export job. Validates membership + idempotent
  /// (returns existing pending job if one exists for this tuple).
  async createExportJob(
    userId: string,
    params: { familyId: string; scope: 'text' | 'full' },
  ) {
    if (!['text', 'full'].includes(params.scope)) {
      throw new BadRequestException('scope must be text or full');
    }
    const membership = await this.prisma.familyMember.findUnique({
      where: { familyId_userId: { familyId: params.familyId, userId } },
    });
    if (!membership) {
      throw new ForbiddenException('Not a member of this family');
    }

    // Idempotent — return existing pending/running job.
    const existing = await this.prisma.chatExportJob.findFirst({
      where: {
        requesterId: userId,
        familyId: params.familyId,
        scope: params.scope,
        status: { in: ['pending', 'running'] },
      },
    });
    if (existing) {
      return { action: 'already_pending' as const, ...existing };
    }

    const id = `cej_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
    return this.prisma.chatExportJob.create({
      data: {
        id,
        requesterId: userId,
        familyId: params.familyId,
        scope: params.scope,
        status: 'pending',
      },
    });
  }

  /// Get a single export job's status (must be owned by caller).
  async getJob(userId: string, jobId: string) {
    const job = await this.prisma.chatExportJob.findUnique({ where: { id: jobId } });
    if (!job) throw new NotFoundException('Export job not found');
    if (job.requesterId !== userId) throw new ForbiddenException('Not the owner of this job');
    return job;
  }

  /// List the caller's recent export jobs (newest first).
  async listMyJobs(userId: string, limit: number = 20) {
    return this.prisma.chatExportJob.findMany({
      where: { requesterId: userId },
      orderBy: { createdAt: 'desc' },
      take: Math.min(limit, 100),
    });
  }

  /// Cancel a pending job (the runner will skip it on next poll).
  /// Running/completed jobs can't be cancelled.
  async cancelJob(userId: string, jobId: string) {
    const job = await this.prisma.chatExportJob.findUnique({ where: { id: jobId } });
    if (!job) throw new NotFoundException('Export job not found');
    if (job.requesterId !== userId) throw new ForbiddenException('Not the owner of this job');
    if (job.status !== 'pending') {
      throw new BadRequestException(`Cannot cancel job in status: ${job.status}`);
    }
    return this.prisma.chatExportJob.update({
      where: { id: jobId },
      data: { status: 'failed', failureReason: 'cancelled_by_user' },
    });
  }
}
