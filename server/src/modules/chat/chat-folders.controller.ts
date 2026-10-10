// server/src/modules/chat/chat-folders.controller.ts
//
// DAXELO KINREL — Tier 3 Feature 3.1: Chat Folders — Controller

import { Body, Controller, Delete, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { ChatFoldersService, ChatFolderRuleType } from './chat-folders.service';

@Controller('chat/folders')
@UseGuards(JwtAuthGuard)
export class ChatFoldersController {
  constructor(private readonly service: ChatFoldersService) {}

  @Get()
  async list(@CurrentUser('id') userId: string) {
    return this.service.listFolders(userId);
  }

  @Post()
  async create(
    @CurrentUser('id') userId: string,
    @Body() body: {
      name: string;
      iconEmoji?: string | null;
      ruleType?: ChatFolderRuleType;
      ruleValue?: string | null;
      orderIndex?: number;
      includeUnread?: boolean;
    },
  ) {
    return this.service.createFolder(userId, body);
  }

  @Patch(':id')
  async update(
    @CurrentUser('id') userId: string,
    @Param('id') id: string,
    @Body() body: Partial<{
      name: string;
      iconEmoji: string | null;
      ruleType: ChatFolderRuleType;
      ruleValue: string | null;
      orderIndex: number;
      includeUnread: boolean;
    }>,
  ) {
    return this.service.updateFolder(userId, id, body);
  }

  @Delete(':id')
  async delete(
    @CurrentUser('id') userId: string,
    @Param('id') id: string,
  ) {
    return this.service.deleteFolder(userId, id);
  }

  @Post('reorder')
  async reorder(
    @CurrentUser('id') userId: string,
    @Body() body: { folderIds: string[] },
  ) {
    return this.service.reorderFolders(userId, body.folderIds ?? []);
  }
}
