// server/src/modules/chat/chat-export-runner.service.ts
//
// DAXELO KINREL — Tier 5 Feature 5.4 follow-up: Chat Export Runner
//
// Processes pending ChatExportJob rows. For each job:
//   1. SELECT all messages in the family chat (sorted by createdAt ASC).
//   2. Format as plain text (scope='text') OR a ZIP with media
//      (scope='full'). For 'full', we download each mediaUrl + zip them.
//   3. Upload the resulting file to Supabase Storage with a 7-day expiry.
//   4. Update the job row with status='completed', resultUrl, resultSizeBytes,
//      messageCount.
//
// On any failure, the job is marked status='failed' with failureReason.
//
// The runner is triggered two ways:
//   • @Cron(EVERY_MINUTE) — picks up pending jobs + processes them.
//   • On startup — so a job created while the server was down gets
//     processed immediately.
//
// NOTE: For scope='full' (ZIP with media), this needs the `adm-zip` package
// added to the server's package.json. The current implementation only
// handles scope='text' fully; 'full' returns a placeholder text file with
// a TODO note for you to wire in the ZIP packaging when you install adm-zip.

import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';
import { PrismaService } from '../../prisma/prisma.service';

@Injectable()
export class ChatExportRunnerService {
  private readonly logger = new Logger(ChatExportRunnerService.name);

  constructor(private readonly prisma: PrismaService) {}

  /// Per-minute cron — picks up pending jobs + processes them.
  @Cron(CronExpression.EVERY_MINUTE)
  async processPendingJobs() {
    try {
      const pendingJobs = await this.prisma.chatExportJob.findMany({
        where: { status: 'pending' },
        orderBy: { createdAt: 'asc' },
        take: 5, // cap at 5 per minute to avoid memory spikes
      });

      if (pendingJobs.length === 0) return;

      this.logger.log(`Chat export runner: processing ${pendingJobs.length} pending job(s)`);
      for (const job of pendingJobs) {
        await this.processJob(job.id);
      }
    } catch (err: any) {
      this.logger.error(`Chat export runner failed: ${err?.message}`, err?.stack);
    }
  }

  /// Fire-and-forget bootstrap call on app startup.
  async processOnStartup() {
    return this.processPendingJobs();
  }

  /// Process a single job by ID. Marks it 'running', builds the export,
  /// marks it 'completed' or 'failed'.
  async processJob(jobId: string) {
    // Mark as running (defensive — skip if already running).
    const job = await this.prisma.chatExportJob.findUnique({ where: { id: jobId } });
    if (!job) {
      this.logger.warn(`Chat export runner: job ${jobId} not found`);
      return;
    }
    if (job.status !== 'pending') {
      this.logger.debug(`Chat export runner: job ${jobId} is ${job.status}, skipping`);
      return;
    }

    try {
      await this.prisma.chatExportJob.update({
        where: { id: jobId },
        data: { status: 'running', updatedAt: new Date() },
      });

      // Verify the requester is still a member of the family (might
      // have left between create + process).
      const membership = await this.prisma.familyMember.findUnique({
        where: { familyId_userId: { familyId: job.familyId, userId: job.requesterId } },
        select: { id: true },
      });
      if (!membership) {
        throw new Error('requester_no_longer_member');
      }

      // Fetch the messages (paginated — cap at 10000 to bound runtime).
      const messages = await this.prisma.chatMessage.findMany({
        where: {
          familyId: job.familyId,
          isDeletedForEveryone: false,
        },
        select: {
          id: true,
          senderName: true,
          content: true,
          messageType: true,
          createdAt: true,
          mediaUrl: true,
          caption: true,
          isEdited: true,
        },
        orderBy: { createdAt: 'asc' },
        take: 10000,
      });

      // Build the export content.
      const { content, sizeBytes, format } = await this.buildExport(
        job.scope,
        messages,
        job.familyId,
      );

      // For now, we DON'T actually upload to storage — we store the
      // content as a data URL in resultUrl. This is a placeholder;
      // the real implementation should upload to Supabase Storage
      // (chat-exports bucket) + return a signed URL with 7-day expiry.
      //
      // TODO: replace this with a real storage upload when you've
      // configured the Supabase Storage bucket + service role key
      // on the NestJS server.
      const resultUrl = this.toDataUrl(content, format);

      await this.prisma.chatExportJob.update({
        where: { id: jobId },
        data: {
          status: 'completed',
          resultUrl,
          resultSizeBytes: BigInt(sizeBytes),
          resultFormat: format,
          messageCount: messages.length,
          completedAt: new Date(),
          expiresAt: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000), // 7 days
          updatedAt: new Date(),
        },
      });

      this.logger.log(
        `Chat export runner: job ${jobId} completed (${messages.length} messages, ${sizeBytes} bytes, ${format})`,
      );
    } catch (err: any) {
      this.logger.error(
        `Chat export runner: job ${jobId} failed: ${err?.message}`,
        err?.stack,
      );
      await this.prisma.chatExportJob.update({
        where: { id: jobId },
        data: {
          status: 'failed',
          failureReason: err?.message ?? 'unknown_error',
          updatedAt: new Date(),
        },
      }).catch(() => {}); // swallow — we don't want a failed update to mask the original error
    }
  }

  /// Build the export content for the given scope.
  /// Returns the content + its byte size + the format ('txt' | 'zip').
  private async buildExport(
    scope: string,
    messages: Array<{
      id: string;
      senderName: string;
      content: string;
      messageType: string;
      createdAt: Date;
      mediaUrl: string | null;
      caption: string | null;
      isEdited: boolean;
    }>,
    familyId: string,
  ): Promise<{ content: string; sizeBytes: number; format: 'txt' | 'zip' }> {
    if (scope === 'full') {
      // For 'full' scope, we'd download each mediaUrl + zip them.
      // Without adm-zip installed, we fall back to text + note the TODO.
      const text = this.formatAsText(messages, familyId, true /* includeMediaNote */);
      return {
        content: text,
        sizeBytes: Buffer.byteLength(text, 'utf8'),
        format: 'txt', // TODO: switch to 'zip' when adm-zip is wired in
      };
    }
    // Default: text-only export.
    const text = this.formatAsText(messages, familyId, false);
    return {
      content: text,
      sizeBytes: Buffer.byteLength(text, 'utf8'),
      format: 'txt',
    };
  }

  /// Format messages as a plain-text transcript (matches WhatsApp export
  /// format: `[YYYY-MM-DD HH:MM:SS] SenderName: content`).
  private formatAsText(
    messages: Array<{
      senderName: string;
      content: string;
      messageType: string;
      createdAt: Date;
      mediaUrl: string | null;
      caption: string | null;
      isEdited: boolean;
    }>,
    familyId: string,
    includeMediaNote: boolean,
  ): string {
    const lines: string[] = [
      `# Daxelo Kinrel Chat Export`,
      `Family ID: ${familyId}`,
      `Exported at: ${new Date().toISOString()}`,
      `Messages: ${messages.length}`,
      includeMediaNote
        ? `(Note: full ZIP export with media is a TODO — this is a text-only fallback.)`
        : ``,
      ``,
      `---`,
      ``,
    ];
    for (const m of messages) {
      const ts = m.createdAt.toISOString().replace('T', ' ').replace(/\..+/, '');
      const editedTag = m.isEdited ? ' (edited)' : '';
      let body: string;
      if (m.messageType === 'text') {
        body = m.content;
      } else if (m.messageType === 'photo' || m.messageType === 'video' || m.messageType === 'document') {
        body = `[${m.messageType}${m.caption ? ': ' + m.caption : ''}]${m.mediaUrl ? ' ' + m.mediaUrl : ''}`;
      } else if (m.messageType === 'voiceNote') {
        body = `[voice note${m.caption ? ': ' + m.caption : ''}]${m.mediaUrl ? ' ' + m.mediaUrl : ''}`;
      } else if (m.messageType === 'sticker') {
        body = `[sticker]${m.mediaUrl ? ' ' + m.mediaUrl : ''}`;
      } else if (m.messageType === 'system') {
        body = `[system] ${m.content}`;
      } else {
        body = m.content || `[${m.messageType}]`;
      }
      lines.push(`[${ts}] ${m.senderName}${editedTag}: ${body}`);
    }
    return lines.join('\n');
  }

  /// Convert content to a data URL (placeholder for the real storage upload).
  /// The data URL is a `data:text/plain;base64,...` URL — small exports
  /// (under ~2MB) fit fine; larger exports should use Supabase Storage.
  private toDataUrl(content: string, format: string): string {
    const mime = format === 'zip' ? 'application/zip' : 'text/plain';
    const b64 = Buffer.from(content, 'utf8').toString('base64');
    return `data:${mime};base64,${b64}`;
  }
}
