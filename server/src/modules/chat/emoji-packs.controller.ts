// server/src/modules/chat/emoji-packs.controller.ts
//
// DAXELO KINREL — Tier 4 Feature 4.6: Custom emoji packs — Controller

import { Body, Controller, Delete, Get, Param, Post, Query, UseGuards } from '@nestjs/common';
import { CurrentUser } from '../../common/decorators/current-user.decorator';
import { JwtAuthGuard } from '../../common/guards/jwt-auth.guard';
import { EmojiPacksService } from './emoji-packs.service';

@Controller('chat/emoji-packs')
@UseGuards(JwtAuthGuard)
export class EmojiPacksController {
  constructor(private readonly service: EmojiPacksService) {}

  /// GET /chat/emoji-packs/catalog
  /// List all packs in the global catalog (with `installed` flag).
  @Get('catalog')
  async catalog(@CurrentUser('id') userId: string) {
    return this.service.listCatalog(userId);
  }

  /// GET /chat/emoji-packs/installed
  /// List only the caller's installed packs + their items.
  @Get('installed')
  async installed(@CurrentUser('id') userId: string) {
    return this.service.listInstalled(userId);
  }

  /// GET /chat/emoji-packs/search?q=party
  /// Search installed packs' items by keyword.
  @Get('search')
  async search(
    @CurrentUser('id') userId: string,
    @Query('q') q: string,
    @Query('limit') limit?: string,
  ) {
    return this.service.searchItems(userId, q ?? '', limit ? parseInt(limit, 10) : 20);
  }

  /// POST /chat/emoji-packs/:packId/install
  @Post(':packId/install')
  async install(@CurrentUser('id') userId: string, @Param('packId') packId: string) {
    return this.service.install(userId, packId);
  }

  /// POST /chat/emoji-packs/:packId/uninstall
  @Post(':packId/uninstall')
  async uninstall(@CurrentUser('id') userId: string, @Param('packId') packId: string) {
    return this.service.uninstall(userId, packId);
  }

  // ── Admin / pack-management endpoints ──────────────────────────────

  /// POST /chat/emoji-packs
  /// Create a new pack in the global catalog.
  @Post()
  async create(
    @CurrentUser('id') userId: string,
    @Body() body: { name: string; thumbUrl?: string | null; isAnimated?: boolean; isOfficial?: boolean; publisherName?: string | null },
  ) {
    return this.service.createPack(userId, body);
  }

  /// POST /chat/emoji-packs/:packId/items
  /// Add an emoji to a pack.
  @Post(':packId/items')
  async addItem(
    @CurrentUser('id') userId: string,
    @Param('packId') packId: string,
    @Body() body: { emojiName: string; imageUrl: string; lottieUrl?: string | null; keywords?: string[] },
  ) {
    return this.service.addEmojiToPack(userId, packId, body);
  }
}
