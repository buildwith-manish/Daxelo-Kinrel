// server/src/modules/chat/chat-folders.service.ts
//
// DAXELO KINREL — Tier 3 Feature 3.1: Chat Folders — Service
//
// Wraps the fn_save_chat_folder + fn_list_chat_folders RPCs.
// The Flutter inbox renders a horizontal folder bar at the top using
// these folders, each folder filters the inbox by its ruleType +
// ruleValue (+ optional includeUnread additive filter).

import { Injectable, BadRequestException, NotFoundException, ForbiddenException, Logger } from '@nestjs/common';
import { PrismaService } from '../../prisma/prisma.service';

export type ChatFolderRuleType = 'all' | 'unread' | 'family' | 'dm' | 'by-name' | 'by-user-id';

@Injectable()
export class ChatFoldersService {
  private readonly logger = new Logger(ChatFoldersService.name);

  constructor(private readonly prisma: PrismaService) {}

  async listFolders(userId: string) {
    return this.prisma.chatFolder.findMany({
      where: { userId },
      orderBy: [{ orderIndex: 'asc' }, { createdAt: 'asc' }],
    });
  }

  async createFolder(
    userId: string,
    params: {
      name: string;
      iconEmoji?: string | null;
      ruleType?: ChatFolderRuleType;
      ruleValue?: string | null;
      orderIndex?: number;
      includeUnread?: boolean;
    },
  ) {
    const name = params.name?.trim();
    if (!name) throw new BadRequestException('Folder name is required');
    if (name.length > 50) throw new BadRequestException('Folder name must be at most 50 characters');
    const ruleType = params.ruleType ?? 'all';
    if (!['all', 'unread', 'family', 'dm', 'by-name', 'by-user-id'].includes(ruleType)) {
      throw new BadRequestException('Invalid ruleType');
    }
    // by-name and by-user-id require ruleValue.
    if ((ruleType === 'by-name' || ruleType === 'by-user-id') && !params.ruleValue?.trim()) {
      throw new BadRequestException(`ruleValue is required for ruleType=${ruleType}`);
    }

    const id = `cf_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
    try {
      return await this.prisma.chatFolder.create({
        data: {
          id,
          userId,
          name,
          iconEmoji: params.iconEmoji ?? null,
          ruleType,
          ruleValue: params.ruleValue ?? null,
          orderIndex: params.orderIndex ?? 0,
          includeUnread: params.includeUnread ?? false,
        },
      });
    } catch (err: any) {
      // P2002 = unique constraint violation (case-insensitive name already exists).
      if (err?.code === 'P2002') {
        throw new BadRequestException('A folder with this name already exists');
      }
      throw err;
    }
  }

  async updateFolder(
    userId: string,
    folderId: string,
    params: Partial<{
      name: string;
      iconEmoji: string | null;
      ruleType: ChatFolderRuleType;
      ruleValue: string | null;
      orderIndex: number;
      includeUnread: boolean;
    }>,
  ) {
    const existing = await this.prisma.chatFolder.findUnique({ where: { id: folderId } });
    if (!existing) throw new NotFoundException('Folder not found');
    if (existing.userId !== userId) throw new ForbiddenException('Not the owner of this folder');

    const data: any = {};
    if (params.name !== undefined) {
      const name = params.name.trim();
      if (!name) throw new BadRequestException('Folder name cannot be empty');
      data.name = name;
    }
    if (params.iconEmoji !== undefined) data.iconEmoji = params.iconEmoji;
    if (params.ruleType !== undefined) {
      if (!['all', 'unread', 'family', 'dm', 'by-name', 'by-user-id'].includes(params.ruleType)) {
        throw new BadRequestException('Invalid ruleType');
      }
      data.ruleType = params.ruleType;
    }
    if (params.ruleValue !== undefined) data.ruleValue = params.ruleValue;
    if (params.orderIndex !== undefined) data.orderIndex = params.orderIndex;
    if (params.includeUnread !== undefined) data.includeUnread = params.includeUnread;

    try {
      return await this.prisma.chatFolder.update({
        where: { id: folderId },
        data,
      });
    } catch (err: any) {
      if (err?.code === 'P2002') {
        throw new BadRequestException('A folder with this name already exists');
      }
      throw err;
    }
  }

  async deleteFolder(userId: string, folderId: string) {
    const existing = await this.prisma.chatFolder.findUnique({ where: { id: folderId } });
    if (!existing) throw new NotFoundException('Folder not found');
    if (existing.userId !== userId) throw new ForbiddenException('Not the owner of this folder');
    await this.prisma.chatFolder.delete({ where: { id: folderId } });
    return { success: true, deleted: folderId };
  }

  /// Reorder folders — accepts an ordered list of folder IDs and writes
  /// the orderIndex based on the array position. Used by the Flutter
  /// drag-to-reorder UI.
  async reorderFolders(userId: string, orderedFolderIds: string[]) {
    if (orderedFolderIds.length === 0) return { success: true };

    // Verify all the folders belong to the caller.
    const folders = await this.prisma.chatFolder.findMany({
      where: { id: { in: orderedFolderIds }, userId },
      select: { id: true },
    });
    if (folders.length !== orderedFolderIds.length) {
      throw new ForbiddenException('One or more folders not owned by the caller');
    }

    // Update each folder's orderIndex in a transaction.
    await this.prisma.$transaction(
      orderedFolderIds.map((id, idx) =>
        this.prisma.chatFolder.update({
          where: { id },
          data: { orderIndex: idx },
        }),
      ),
    );
    return { success: true, reordered: orderedFolderIds.length };
  }
}
