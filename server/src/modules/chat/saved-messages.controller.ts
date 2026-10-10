// server/src/modules/chat/saved-messages.controller.ts
//
// DAXELO KINREL — Tier 1 Feature 1.1: Saved Messages — Controller
//
// Single REST endpoint that returns the user's self-DM preview for the
// inbox "Saved Messages" row. The actual DM-with-self persistence goes
// through the existing DirectMessage table (RLS already permits
// senderId = receiverId = auth.uid()), so this controller just wraps
// the fn_get_saved_messages_inbox RPC.

import { Controller, Get, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { PrismaService } from '../../prisma/prisma.service';

@Controller('chat/saved-messages')
@UseGuards(JwtAuthGuard)
export class SavedMessagesController {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * GET /chat/saved-messages
   * Returns the user's self-DM preview (or hasSavedMessages=false).
   * Used by the Flutter inbox to render the "Saved Messages" row at
   * the top of the DM section.
   */
  @Get()
  async getInboxPreview(@CurrentUser('id') userId: string) {
    const rows = (await this.prisma.$queryRaw`
      SELECT fn_get_saved_messages_inbox() AS result;
    `) as Array<{ result: unknown }>;

    if (!Array.isArray(rows) || rows.length === 0) {
      return { success: false, hasSavedMessages: false, otherUserId: userId };
    }

    const raw = rows[0]?.result;
    if (raw == null) {
      return { success: false, hasSavedMessages: false, otherUserId: userId };
    }

    try {
      const obj = typeof raw === 'string' ? JSON.parse(raw) : (raw as any);
      return obj;
    } catch {
      return { success: false, hasSavedMessages: false, otherUserId: userId };
    }
  }
}
